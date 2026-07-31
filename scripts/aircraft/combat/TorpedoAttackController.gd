extends Node
class_name TorpedoAttackController

signal state_changed(state: State)
signal torpedo_released(aircraft_id: int, released_count: int)
signal attack_finished(released_count: int, aborted: bool, reason: StringName)

enum State {
	IDLE,
	APPROACHING,
	ALIGNING,
	DESCENDING,
	ATTACK_RUN,
	RELEASING,
	ESCAPING,
	COMPLETED,
	ABORTED,
}

const EPSILON := 0.0001

var state: State = State.IDLE
var owner_squadron: AircraftSquadron
var movement: SquadronMovementController
var battle_services: BattleServices
var attack_profile: TorpedoAttackProfile
var command: TorpedoAttackCommand
var released_aircraft_count := 0
var abort_reason: StringName

var _released_aircraft_ids: Dictionary = {}
var _resolved_aircraft_ids: Dictionary = {}
var _last_state_name: StringName


func setup(
		squadron: AircraftSquadron,
		movement_controller: SquadronMovementController,
		services: BattleServices
) -> void:
	shutdown()
	owner_squadron = squadron
	movement = movement_controller
	battle_services = services
	attack_profile = squadron.get_torpedo_attack_profile() \
		if squadron != null else null
	_set_state(State.IDLE)


func shutdown() -> void:
	if is_active():
		abort(&"shutdown", false)
	owner_squadron = null
	movement = null
	battle_services = null
	attack_profile = null
	command = null
	_released_aircraft_ids.clear()
	_resolved_aircraft_ids.clear()
	released_aircraft_count = 0
	abort_reason = StringName()
	state = State.IDLE
	set_process(false)
	set_physics_process(false)


func can_begin_attack(next_command: TorpedoAttackCommand) -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and movement != null \
		and attack_profile != null \
		and attack_profile.validate().is_empty() \
		and next_command != null \
		and next_command.actual_run_distance_m + 0.01 \
			>= next_command.minimum_run_distance_m \
		and next_command.attack_direction.length_squared() > EPSILON \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.TORPEDO_BOMBER \
		and owner_squadron.has_torpedo_payload() \
		and owner_squadron.state not in [
			AircraftSquadron.State.RETURNING,
			AircraftSquadron.State.RECOVERING,
			AircraftSquadron.State.DESTROYED,
		] \
		and not is_active()


func begin_attack(next_command: TorpedoAttackCommand) -> bool:
	if not can_begin_attack(next_command):
		return false
	command = next_command.duplicate_command()
	command.attack_direction.y = 0.0
	command.attack_direction = command.attack_direction.normalized()
	_released_aircraft_ids.clear()
	_resolved_aircraft_ids.clear()
	released_aircraft_count = 0
	abort_reason = StringName()
	owner_squadron.set_combat_formation_enabled(true)
	_set_attack_destination(
		_with_altitude(
			command.approach_point,
			owner_squadron.squadron_data.aircraft_data.operating_altitude_m
		),
		&"torpedo_approach"
	)
	_set_state(State.APPROACHING)
	return true


func update_attack(delta: float) -> void:
	if not is_active() or command == null \
			or owner_squadron == null \
			or not is_instance_valid(owner_squadron):
		return
	if owner_squadron.get_alive_aircraft().is_empty():
		abort(&"no_aircraft", false)
		return
	match state:
		State.APPROACHING:
			_update_approaching(delta)
		State.ALIGNING:
			_update_aligning(delta)
		State.DESCENDING:
			_update_descending(delta)
		State.ATTACK_RUN:
			_update_attack_run(delta)
		State.RELEASING:
			_update_releasing(delta)
		State.ESCAPING:
			_update_escaping(delta)
		_:
			pass


func abort(reason: StringName, begin_escape: bool = true) -> void:
	if not is_active():
		return
	abort_reason = reason
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.cancel_pending_weapon_release()
	if begin_escape and command != null \
			and owner_squadron != null \
			and is_instance_valid(owner_squadron):
		_begin_escape()
		return
	_finish(true)


func is_active() -> bool:
	return state in [
		State.APPROACHING,
		State.ALIGNING,
		State.DESCENDING,
		State.ATTACK_RUN,
		State.RELEASING,
		State.ESCAPING,
	]


func get_state_name() -> StringName:
	return StringName(State.keys()[int(state)])


func get_command() -> TorpedoAttackCommand:
	return command


func get_released_aircraft_count() -> int:
	return released_aircraft_count


func _update_approaching(delta: float) -> void:
	var target := _with_altitude(
		command.approach_point,
		owner_squadron.squadron_data.aircraft_data.operating_altitude_m
	)
	_advance_formation(target, delta)
	if movement.has_formation_arrived(target):
		_set_attack_destination(
			_with_altitude(command.entry_point, attack_profile.attack_entry_altitude_m),
			&"torpedo_entry"
		)
		_set_state(State.ALIGNING)


func _update_aligning(delta: float) -> void:
	var entry_target := _with_altitude(
		command.entry_point,
		attack_profile.attack_entry_altitude_m
	)
	_advance_formation(entry_target, delta)
	var forward := owner_squadron.get_formation_forward()
	forward.y = 0.0
	var angle := rad_to_deg(forward.angle_to(command.attack_direction)) \
		if forward.length_squared() > EPSILON else 180.0
	if angle <= attack_profile.alignment_tolerance_deg:
		_set_state(State.DESCENDING)


func _update_descending(delta: float) -> void:
	var entry_target := _with_altitude(
		command.entry_point,
		attack_profile.attack_entry_altitude_m
	)
	_advance_formation(entry_target, delta)
	if movement.has_formation_arrived(entry_target):
		_set_attack_destination(
			_with_altitude(command.actual_release_point, attack_profile.release_altitude_m),
			&"torpedo_release"
		)
		_set_state(State.ATTACK_RUN)


func _update_attack_run(delta: float) -> void:
	var release_target := _with_altitude(
		command.actual_release_point,
		attack_profile.release_altitude_m
	)
	var direct_vector := release_target - owner_squadron.formation_center
	if direct_vector.length_squared() <= EPSILON:
		direct_vector = command.attack_direction
	owner_squadron.apply_direct_flight(
		direct_vector.normalized(),
		attack_profile.attack_run_speed_mps,
		delta,
		release_target.y
	)
	var remaining_along := (
		release_target - owner_squadron.formation_center
	).dot(command.attack_direction)
	if remaining_along <= attack_profile.release_point_tolerance_m:
		_set_state(State.RELEASING)


func _update_releasing(delta: float) -> void:
	owner_squadron.apply_direct_flight(
		command.attack_direction,
		attack_profile.attack_run_speed_mps,
		delta,
		command.command_plane_height_m + attack_profile.release_altitude_m
	)
	_release_ready_aircraft()
	if _all_surviving_aircraft_resolved():
		if released_aircraft_count <= 0:
			abort_reason = &"no_releasable_payload"
		_begin_escape()
		return
	var along_after_release := (
		owner_squadron.formation_center - command.actual_release_point
	).dot(command.attack_direction)
	if along_after_release >= attack_profile.release_grace_distance_m:
		abort_reason = &"release_window_missed"
		_begin_escape()


func _release_ready_aircraft() -> void:
	for aircraft in owner_squadron.get_alive_aircraft():
		var id := aircraft.get_instance_id()
		if _resolved_aircraft_ids.has(id):
			continue
		var weapon := aircraft.weapon_controller
		if weapon == null or weapon.weapon_data == null \
				or weapon.weapon_data.weapon_type \
					!= AircraftWeaponData.WeaponType.TORPEDO \
				or not weapon.has_ammunition():
			_resolved_aircraft_ids[id] = true
			continue
		if not _aircraft_meets_release_envelope(aircraft):
			continue
		var request := AirDroppedTorpedoLaunchRequest.new()
		request.source_aircraft = aircraft
		request.source_squadron = owner_squadron
		request.launch_position = aircraft \
			.get_payload_release_transform().origin
		request.launch_direction = command.attack_direction
		request.aircraft_velocity = aircraft.get_world_velocity()
		request.target_point = command.escape_point
		request.target_ship = command.target_ship
		request.torpedo_data = weapon.weapon_data.projectile_data \
			as TorpedoProjectileData
		request.command_id = command.command_id
		var release_result := weapon.release_air_dropped_torpedo(request)
		if release_result.success:
			_released_aircraft_ids[id] = true
			_resolved_aircraft_ids[id] = true
			released_aircraft_count += 1
			torpedo_released.emit(id, released_aircraft_count)


func _aircraft_meets_release_envelope(aircraft: AircraftUnit) -> bool:
	var altitude := aircraft.global_position.y - command.command_plane_height_m
	if altitude < attack_profile.release_altitude_m - 2.0 \
			or altitude > attack_profile.maximum_release_altitude_m:
		return false
	var speed := aircraft.get_world_velocity().length()
	if speed < attack_profile.minimum_release_speed_mps \
			or speed > attack_profile.maximum_release_speed_mps:
		return false
	var forward := aircraft.get_forward_direction()
	forward.y = 0.0
	if forward.length_squared() <= EPSILON \
			or rad_to_deg(forward.angle_to(command.attack_direction)) \
				> attack_profile.alignment_tolerance_deg:
		return false
	var release_offset := aircraft.global_position - command.actual_release_point
	release_offset.y = 0.0
	return absf(release_offset.dot(command.attack_direction)) \
		<= attack_profile.release_point_tolerance_m


func _all_surviving_aircraft_resolved() -> bool:
	var alive := owner_squadron.get_alive_aircraft()
	if alive.is_empty():
		return true
	for aircraft in alive:
		if not _resolved_aircraft_ids.has(aircraft.get_instance_id()):
			return false
	return true


func _begin_escape() -> void:
	if state == State.ESCAPING:
		return
	owner_squadron.restore_formation_flight()
	_set_attack_destination(
		_with_altitude(command.escape_point, attack_profile.escape_altitude_m),
		&"torpedo_escape"
	)
	_set_state(State.ESCAPING)


func _update_escaping(delta: float) -> void:
	var escape_target := _with_altitude(
		command.escape_point,
		attack_profile.escape_altitude_m
	)
	_advance_formation(escape_target, delta)
	if movement.has_formation_arrived(escape_target):
		owner_squadron.finish_direct_flight_holding(escape_target.y)
		_finish(not abort_reason.is_empty())


func _advance_formation(target: Vector3, delta: float) -> void:
	movement.advance_formation_center(target, delta)
	movement.update_formation_targets()


func _set_attack_destination(target: Vector3, command_type: StringName) -> void:
	owner_squadron.set_mission_destination(target, true, command_type)


func _with_altitude(point: Vector3, altitude_m: float) -> Vector3:
	var result := point
	result.y = command.command_plane_height_m + altitude_m
	return result


func _finish(aborted: bool) -> void:
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.set_combat_formation_enabled(false)
		owner_squadron.restore_formation_flight()
	_set_state(State.ABORTED if aborted else State.COMPLETED)
	attack_finished.emit(released_aircraft_count, aborted, abort_reason)
	command = null


func _set_state(next_state: State) -> void:
	if state == next_state and _last_state_name == StringName(State.keys()[int(next_state)]):
		return
	state = next_state
	_last_state_name = StringName(State.keys()[int(state)])
	state_changed.emit(state)
