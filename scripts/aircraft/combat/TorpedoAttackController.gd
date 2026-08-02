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

# Optional callback that returns a fresh TorpedoAttackCommand for the current
# target, injected by the AI mission controller. Invoked once just before the
# solution is locked so the attack commits to the latest predicted geometry.
var solution_refresher: Callable = Callable()

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
	solution_refresher = Callable()
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
	if state != State.ESCAPING and _is_target_lost():
		_handle_target_lost()
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


func can_update_attack_solution() -> bool:
	# The AI may re-aim only while still lining the run up. Once the solution is
	# locked (just before the descent) or the run has committed, the geometry is
	# frozen so the torpedoes drop where they were planned.
	return command != null \
		and not command.solution_locked \
		and state in [State.APPROACHING, State.ALIGNING]


func update_attack_solution(updated_command: TorpedoAttackCommand) -> bool:
	# Guarded re-aim used by the AI mission controller during the approach. The
	# command is only replaced when it is a newer revision of the SAME tracked
	# attack against the SAME target and the geometry is still valid; otherwise
	# the current solution is kept untouched.
	if not can_update_attack_solution():
		return false
	if not _is_valid_solution_update(updated_command):
		return false
	_apply_solution(updated_command)
	return true


func get_prediction_debug_snapshot() -> AircraftAttackPredictionDebugSnapshot:
	var snapshot := AircraftAttackPredictionDebugSnapshot.new()
	if command == null:
		return snapshot
	snapshot.entry_point = command.entry_point
	snapshot.release_point = command.actual_release_point
	snapshot.predicted_collision_point = command.predicted_collision_point
	snapshot.predicted_target_center = command.predicted_impact_position
	snapshot.arming_distance_m = command.arming_distance_m
	snapshot.collision_margin_m = command.collision_margin_m
	snapshot.prediction_error_margin_m = command.prediction_error_margin_m
	snapshot.safe_run_distance_m = command.torpedo_safe_run_distance_m
	snapshot.solution_revision = command.solution_revision
	snapshot.solution_locked = command.solution_locked
	snapshot.attack_state = get_state_name()
	if command.target_ship != null and is_instance_valid(command.target_ship):
		snapshot.target_instance_id = command.target_ship.get_instance_id()
		snapshot.target_position = command.target_ship.global_position
		snapshot.target_velocity = command.target_ship.get_world_velocity()
	return snapshot


func abort_before_attack(reason: StringName) -> void:
	# Setup/target failures before the run commits: stop cleanly with no escape
	# leg. The mission controller decides whether to re-task or return.
	if not is_active():
		return
	abort_reason = reason
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.cancel_pending_weapon_release()
	_finish(true)


func escape_without_release(reason: StringName) -> void:
	# In-run failures (e.g. the target is gone) before all torpedoes are away:
	# keep the remaining payload, drop the attack-speed override, and climb out
	# along the escape leg instead of dumping torpedoes at a dead target.
	if not is_active():
		return
	if abort_reason.is_empty():
		abort_reason = reason
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.cancel_pending_weapon_release()
	_begin_escape()


func _is_target_lost() -> bool:
	# Only ship-tracked attacks (AI) can lose a target. A command with no
	# target_ship is a position-only drop (e.g. player manual) and is never
	# treated as target-lost.
	if command == null or command.target_ship == null:
		return false
	var target := command.target_ship
	return not is_instance_valid(target) or not target.is_alive()


func _handle_target_lost() -> void:
	match state:
		State.APPROACHING, State.ALIGNING:
			abort_before_attack(&"target_lost")
		State.DESCENDING, State.ATTACK_RUN:
			escape_without_release(&"target_lost")
		State.RELEASING:
			# Torpedoes already leaving keep running independently; stop dropping
			# the rest and climb out.
			escape_without_release(&"target_lost_during_release")
		_:
			pass


func _finalize_and_lock_solution() -> void:
	# One last refresh against the live target, then freeze. Failure to refresh
	# keeps the last valid solution rather than releasing on stale coordinates.
	if command == null:
		return
	if solution_refresher.is_valid():
		var fresh: Variant = solution_refresher.call()
		if fresh is TorpedoAttackCommand \
				and _is_valid_final_solution(fresh):
			_apply_solution(fresh)
	command.solution_locked = true


func _is_valid_solution_update(updated: TorpedoAttackCommand) -> bool:
	if updated == null or command == null:
		return false
	if updated.target_ship != command.target_ship:
		return false
	if updated.tracking_id != command.tracking_id:
		return false
	if updated.solution_revision <= command.solution_revision:
		return false
	return _is_valid_final_solution(updated)


func _is_valid_final_solution(candidate: TorpedoAttackCommand) -> bool:
	if candidate == null:
		return false
	if candidate.attack_direction.length_squared() <= EPSILON:
		return false
	if candidate.actual_run_distance_m + 0.01 \
			< candidate.minimum_run_distance_m:
		return false
	if candidate.torpedo_safe_run_distance_m + 0.01 \
			< candidate.arming_distance_m:
		return false
	# The release point must sit ahead of the entry point along the attack axis.
	var along := candidate.actual_release_point - candidate.entry_point
	along.y = 0.0
	return along.dot(candidate.attack_direction) > 0.0


func _apply_solution(updated: TorpedoAttackCommand) -> void:
	# Mutate the live command in place so the running state handlers pick up the
	# new geometry next frame while command_id, tracking_id and target_ship (the
	# attack's identity) are preserved.
	command.entry_point = updated.entry_point
	command.requested_release_point = updated.requested_release_point
	command.actual_release_point = updated.actual_release_point
	command.approach_point = updated.approach_point
	command.escape_point = updated.escape_point
	var direction := updated.attack_direction
	direction.y = 0.0
	if direction.length_squared() > EPSILON:
		command.attack_direction = direction.normalized()
	command.requested_run_distance_m = updated.requested_run_distance_m
	command.actual_run_distance_m = updated.actual_run_distance_m
	command.minimum_run_distance_m = updated.minimum_run_distance_m
	command.command_plane_height_m = updated.command_plane_height_m
	command.predicted_impact_position = updated.predicted_impact_position
	command.predicted_collision_point = updated.predicted_collision_point
	command.torpedo_safe_run_distance_m = updated.torpedo_safe_run_distance_m
	command.arming_distance_m = updated.arming_distance_m
	command.collision_margin_m = updated.collision_margin_m
	command.prediction_error_margin_m = updated.prediction_error_margin_m
	command.solution_revision += 1


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
		_finalize_and_lock_solution()
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
