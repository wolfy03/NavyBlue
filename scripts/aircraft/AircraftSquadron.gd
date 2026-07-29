extends Node3D
class_name AircraftSquadron

signal recovery_completed(squadron)
signal squadron_lost(squadron)
signal aircraft_lost(squadron, aircraft: AircraftUnit)
signal formation_activated(squadron)
signal return_requested(squadron)
signal player_selection_changed(selected: bool)

enum State {
	FORMING,
	EN_ROUTE,
	HOLDING,
	RETURNING,
	RECOVERING,
	DESTROYED,
}

enum CommandAuthority {
	AI,
	PLAYER,
}

enum ManualDiveCommandState {
	NONE,
	READY,
	DIVING,
	RELEASED,
	PULLING_OUT,
}

const EPSILON := 0.0001

@onready var mission_controller: AircraftMissionController = get_node_or_null(
	"AircraftMissionController"
) as AircraftMissionController
@onready var dive_bomb_controller: DiveBombAttackController = \
	get_node_or_null("DiveBombAttackController") as DiveBombAttackController
@onready var selection_indicator: MeshInstance3D = \
	get_node_or_null("SelectionIndicator") as MeshInstance3D

@export var manual_return_after_release := false

var squadron_data: SquadronData
var aircraft_units: Array[AircraftUnit] = []
var state: State = State.FORMING
var destination: Vector3 = Vector3.ZERO
var formation_center: Vector3 = Vector3.ZERO
var command_authority: CommandAuthority = CommandAuthority.AI
var player_selected := false
var manual_dive_state: ManualDiveCommandState = \
	ManualDiveCommandState.NONE

var _owner_carrier_ref: WeakRef
var _formation_forward: Vector3 = Vector3.FORWARD
var _launch_elapsed_sec := 0.0
var _next_aircraft_to_activate := 0
var _completion_emitted := false
var _release_queue: Array[AircraftUnit] = []
var _release_interval_left := 0.0
var _release_target_position := Vector3.ZERO
var _release_target_velocity := Vector3.ZERO
var _carrier_unavailable_cleanup_left := -1.0
var _requested_aircraft_count := -1
var _formation_activated_emitted := false
var _team: StringName = &"neutral"
var _combat_formation_enabled := false
var _fighter_target_squadron_ref: WeakRef
var _manual_move_target := Vector3.ZERO
var _has_manual_move_target := false
var _manual_attack_target_ref: WeakRef


func setup(
		carrier: ShipUnit,
		data: SquadronData,
		aircraft_parent: Node,
		launch_aircraft_count: int = -1
) -> void:
	_owner_carrier_ref = weakref(carrier) \
		if carrier != null and is_instance_valid(carrier) else null
	squadron_data = data
	_requested_aircraft_count = launch_aircraft_count
	if get_parent() == null and aircraft_parent != null:
		aircraft_parent.add_child(self)
	var owner_carrier := get_owner_carrier()
	if owner_carrier == null or squadron_data == null \
			or squadron_data.aircraft_data == null:
		state = State.DESTROYED
		return
	_team = owner_carrier.team
	add_to_group(&"aircraft_squadrons")
	formation_center = _get_carrier_launch_position()
	_formation_forward = -owner_carrier.global_transform.basis.z.normalized()
	if _formation_forward.length_squared() <= EPSILON:
		_formation_forward = Vector3.FORWARD
	_spawn_aircraft()
	if mission_controller != null:
		mission_controller.setup(self)
	if dive_bomb_controller != null:
		dive_bomb_controller.setup(self)
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.register_squadron(self)
	set_physics_process(false)


func launch_to(world_position: Vector3) -> void:
	if state == State.DESTROYED or squadron_data == null:
		return
	destination = _clamp_destination_to_combat_radius(world_position)
	state = State.EN_ROUTE
	_launch_elapsed_sec = 0.0
	_next_aircraft_to_activate = 0
	_activate_next_aircraft()
	set_physics_process(true)


func request_return() -> void:
	if state == State.RECOVERING or state == State.DESTROYED:
		return
	if get_owner_carrier() == null:
		_mark_destroyed()
		return
	clear_fighter_targets()
	cancel_pending_weapon_release()
	set_combat_formation_enabled(false)
	set_player_selected(false)
	manual_dive_state = ManualDiveCommandState.NONE
	_has_manual_move_target = false
	_manual_attack_target_ref = null
	if dive_bomb_controller != null:
		dive_bomb_controller.cancel()
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_intercept_assignment(self)
	state = State.RETURNING
	return_requested.emit(self)
	set_physics_process(true)


func get_alive_aircraft_count() -> int:
	_prune_aircraft()
	var count := 0
	for aircraft in aircraft_units:
		if is_instance_valid(aircraft) \
				and aircraft.health != null \
				and aircraft.health.is_alive():
			count += 1
	return count


func get_alive_aircraft() -> Array[AircraftUnit]:
	_prune_aircraft()
	var result: Array[AircraftUnit] = []
	for aircraft in aircraft_units:
		if is_instance_valid(aircraft) and aircraft.is_alive():
			result.append(aircraft)
	return result


func assign_strike_mission(
		target_ship: Node3D,
		mission_data: AirMissionData
) -> bool:
	return mission_controller != null \
		and mission_controller.assign_ship_strike(target_ship, mission_data)


func assign_move_mission(
		world_position: Vector3,
		mission_data: AirMissionData
) -> bool:
	return mission_controller != null \
		and mission_controller.assign_move(world_position, mission_data)


func assign_return_mission(mission_data: AirMissionData) -> bool:
	return mission_controller != null \
		and mission_controller.assign_return(mission_data)


func assign_intercept_mission(
		target_squadron: AircraftSquadron,
		mission_data: AirMissionData,
		rng_seed: int = 0
) -> bool:
	return mission_controller != null \
		and mission_controller.assign_aircraft_intercept(
			target_squadron,
			mission_data,
			rng_seed
		)


func get_aircraft_role() -> AircraftData.AircraftRole:
	return squadron_data.aircraft_data.role \
		if squadron_data != null \
		and squadron_data.aircraft_data != null \
		else AircraftData.AircraftRole.RECON


func get_team() -> StringName:
	return _team


func get_fighter_combat_data() -> FighterCombatData:
	return squadron_data.aircraft_data.fighter_combat_data \
		if squadron_data != null \
		and squadron_data.aircraft_data != null else null


func set_command_authority(authority: CommandAuthority) -> void:
	command_authority = authority
	if authority == CommandAuthority.PLAYER:
		clear_fighter_targets()
		for aircraft in aircraft_units:
			if is_instance_valid(aircraft) \
					and aircraft.fighter_combat_controller != null:
				aircraft.fighter_combat_controller.disable_combat()


func is_player_commanded() -> bool:
	return command_authority == CommandAuthority.PLAYER


func set_player_selected(selected: bool) -> void:
	if player_selected == selected:
		return
	player_selected = selected
	if selection_indicator != null:
		selection_indicator.visible = selected
		_update_selection_indicator()
	player_selection_changed.emit(selected)


func cancel_current_mission_for_player_command() -> void:
	if state in [State.RETURNING, State.RECOVERING, State.DESTROYED]:
		return
	cancel_pending_weapon_release()
	clear_fighter_targets()
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_intercept_assignment(self)
	if mission_controller != null:
		mission_controller.cancel_current_mission_for_player_command()


func issue_player_move_command(
		world_position: Vector3,
		attack_target: ShipUnit = null
) -> bool:
	if not _can_accept_player_command():
		return false
	cancel_current_mission_for_player_command()
	if dive_bomb_controller != null:
		dive_bomb_controller.cancel()
	set_command_authority(CommandAuthority.PLAYER)
	manual_dive_state = ManualDiveCommandState.READY \
		if get_aircraft_role() == AircraftData.AircraftRole.DIVE_BOMBER \
		else ManualDiveCommandState.NONE
	_manual_attack_target_ref = weakref(attack_target) \
		if _is_valid_manual_attack_target(attack_target) else null
	var carrier := get_owner_carrier()
	var data := squadron_data.aircraft_data
	_manual_move_target = world_position
	_manual_move_target.y = carrier.global_position.y \
		+ data.operating_altitude_m
	_manual_move_target = _clamp_destination_to_combat_radius(
		_manual_move_target
	)
	_has_manual_move_target = true
	set_mission_destination(_manual_move_target)
	return true


func begin_manual_dive() -> bool:
	if not _can_accept_player_command() \
			or not is_player_commanded() \
			or get_aircraft_role() \
				!= AircraftData.AircraftRole.DIVE_BOMBER \
			or manual_dive_state != ManualDiveCommandState.READY \
			or dive_bomb_controller == null \
			or not has_any_ammunition():
		return false
	cancel_current_mission_for_player_command()
	var target_ship := get_manual_attack_target()
	var target := target_ship.global_position \
		if target_ship != null else (
			_manual_move_target if _has_manual_move_target \
			else formation_center \
				+ get_formation_forward() * 600.0
		)
	target.y = target_ship.global_position.y \
		if target_ship != null else 0.0
	var target_velocity := target_ship.velocity \
		if target_ship is CharacterBody3D else Vector3.ZERO
	if not dive_bomb_controller.begin_dive(target, target_velocity):
		return false
	manual_dive_state = ManualDiveCommandState.DIVING
	return true


func request_manual_bomb_release() -> bool:
	if not is_player_commanded() \
			or manual_dive_state != ManualDiveCommandState.DIVING \
			or dive_bomb_controller == null:
		return false
	var released_count := dive_bomb_controller.release_bombs()
	if released_count <= 0:
		return false
	manual_dive_state = ManualDiveCommandState.PULLING_OUT
	return true


func get_manual_release_block_reason() -> int:
	if dive_bomb_controller == null:
		return int(DiveBombAttackController.ReleaseBlockReason.NOT_DIVING)
	dive_bomb_controller.can_release_bombs()
	return int(dive_bomb_controller.release_block_reason)


func get_manual_attack_target() -> ShipUnit:
	if _manual_attack_target_ref == null:
		return null
	var target := _manual_attack_target_ref.get_ref() as ShipUnit
	return target if _is_valid_manual_attack_target(target) else null


func assign_fighter_targets(
		target_squadron: AircraftSquadron
) -> void:
	if target_squadron == null or not is_instance_valid(target_squadron):
		clear_fighter_targets()
		return
	var targets := target_squadron.get_alive_aircraft()
	if targets.is_empty():
		clear_fighter_targets()
		return
	var current_target_squadron := _fighter_target_squadron_ref.get_ref() \
		as AircraftSquadron \
		if _fighter_target_squadron_ref != null else null
	var needs_assignment := current_target_squadron != target_squadron
	if not needs_assignment:
		for attacker in get_alive_aircraft():
			if attacker.fighter_combat_controller == null \
					or attacker.fighter_combat_controller.get_target() == null:
				needs_assignment = true
				break
	if not needs_assignment:
		return
	_fighter_target_squadron_ref = weakref(target_squadron)
	var attackers := get_alive_aircraft()
	for index in range(attackers.size()):
		var controller := attackers[index].fighter_combat_controller
		if controller != null:
			controller.set_target(targets[index % targets.size()])


func clear_fighter_targets() -> void:
	_fighter_target_squadron_ref = null
	for aircraft in get_alive_aircraft():
		if aircraft.fighter_combat_controller != null:
			aircraft.fighter_combat_controller.clear_target()


func update_fighter_combat(
		delta: float,
		rng: RandomNumberGenerator
) -> Array[FighterShotResult]:
	var results: Array[FighterShotResult] = []
	for aircraft in get_alive_aircraft():
		if aircraft.fighter_combat_controller == null:
			continue
		var result := aircraft.fighter_combat_controller.update_combat(
			delta,
			rng
		)
		if result != null:
			results.append(result)
	return results


func set_combat_formation_enabled(enabled: bool) -> void:
	_combat_formation_enabled = enabled


func get_combat_coordinator() -> AircraftCombatCoordinator:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group(
		&"aircraft_combat_coordinator"
	) as AircraftCombatCoordinator


func request_weapon_release(
		target_position: Vector3,
		target_velocity: Vector3
) -> int:
	return request_weapon_release_for_ready_aircraft(
		target_position,
		target_velocity,
		-INF,
		INF
	)


func request_weapon_release_for_ready_aircraft(
		target_position: Vector3,
		target_velocity: Vector3,
		minimum_altitude_m: float,
		maximum_altitude_m: float
) -> int:
	if is_weapon_release_in_progress():
		return 0
	_release_queue.clear()
	for aircraft in get_alive_aircraft():
		var altitude := aircraft.global_position.y - target_position.y
		if altitude < minimum_altitude_m \
				or altitude > maximum_altitude_m:
			continue
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.can_release():
			_release_queue.append(aircraft)
	_release_target_position = target_position
	_release_target_velocity = target_velocity
	_release_interval_left = 0.0
	return _release_queue.size()


func cancel_pending_weapon_release() -> void:
	_release_queue.clear()
	_release_interval_left = 0.0
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null:
			aircraft.weapon_controller.cancel_pending_release()


func can_release_payload() -> bool:
	if is_weapon_release_in_progress():
		return false
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.can_release():
			return true
	return false


func get_total_remaining_ammunition() -> int:
	var result := 0
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null:
			result += aircraft.weapon_controller.get_remaining_ammunition()
	return result


func has_any_ammunition() -> bool:
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.has_ammunition():
			return true
	return false


func is_weapon_release_in_progress() -> bool:
	if not _release_queue.is_empty():
		return true
	for aircraft in get_alive_aircraft():
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.is_release_in_progress():
			return true
	return false


func get_aircraft_weapon_data() -> AircraftWeaponData:
	return squadron_data.aircraft_data.weapon_data \
		if squadron_data != null \
			and squadron_data.aircraft_data != null else null


func get_formation_forward() -> Vector3:
	return _formation_forward


func get_formation_velocity() -> Vector3:
	return _formation_forward * _get_aircraft_speed()


func get_current_mission_state() -> int:
	return int(mission_controller.get("state")) \
		if mission_controller != null else -1


func get_current_mission_id() -> String:
	var data: Variant = mission_controller.get("mission_data") \
		if mission_controller != null else null
	return data.id if data is AirMissionData else ""


func get_current_target() -> Node3D:
	if mission_controller != null \
			and mission_controller.has_method(&"get_target_squadron"):
		var target_squadron := mission_controller.call(
			&"get_target_squadron"
		) as AircraftSquadron
		if target_squadron != null:
			return target_squadron
	if mission_controller == null \
			or not mission_controller.has_method(&"get_target_ship"):
		return null
	return mission_controller.call(&"get_target_ship") as Node3D


func set_mission_destination(world_position: Vector3) -> void:
	if state == State.RETURNING \
			or state == State.RECOVERING \
			or state == State.DESTROYED:
		return
	destination = _clamp_destination_horizontal(world_position)
	state = State.EN_ROUTE
	set_physics_process(true)


func handle_carrier_unavailable(cleanup_grace_sec: float = 2.0) -> void:
	_owner_carrier_ref = null
	_release_queue.clear()
	set_player_selected(false)
	manual_dive_state = ManualDiveCommandState.NONE
	_has_manual_move_target = false
	_manual_attack_target_ref = null
	if dive_bomb_controller != null:
		dive_bomb_controller.cancel()
	clear_fighter_targets()
	for aircraft in aircraft_units:
		if not is_instance_valid(aircraft):
			continue
		if aircraft.weapon_controller != null:
			aircraft.weapon_controller.disable_weapon_release()
		if aircraft.fighter_combat_controller != null:
			aircraft.fighter_combat_controller.disable_combat()
	if mission_controller != null:
		mission_controller.cancel_mission_due_to_carrier_loss()
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_intercept_assignment(self)
	_carrier_unavailable_cleanup_left = maxf(cleanup_grace_sec, 0.0)
	set_physics_process(true)


func is_recovered() -> bool:
	return state == State.RECOVERING


func get_owner_carrier() -> ShipUnit:
	if _owner_carrier_ref == null:
		return null
	var carrier: Variant = _owner_carrier_ref.get_ref()
	return carrier as ShipUnit if is_instance_valid(carrier) else null


func release_aircraft() -> void:
	clear_fighter_targets()
	for aircraft in aircraft_units:
		if is_instance_valid(aircraft):
			if aircraft.destroyed.is_connected(_on_aircraft_destroyed):
				aircraft.destroyed.disconnect(_on_aircraft_destroyed)
			aircraft.queue_free()
	aircraft_units.clear()


func _physics_process(delta: float) -> void:
	_prune_aircraft()
	if aircraft_units.is_empty():
		_mark_destroyed()
		return
	if _carrier_unavailable_cleanup_left >= 0.0:
		_carrier_unavailable_cleanup_left = maxf(
			0.0,
			_carrier_unavailable_cleanup_left - delta
		)
		if _carrier_unavailable_cleanup_left <= 0.0:
			for aircraft in get_alive_aircraft():
				aircraft.destroy_for_cleanup()
			_mark_destroyed()
			return
	_update_launch_sequence(delta)
	_update_weapon_release_sequence(delta)
	if mission_controller != null \
			and not is_player_commanded() \
			and state not in [
				State.RETURNING,
				State.RECOVERING,
				State.DESTROYED,
			]:
		mission_controller.update_mission(delta)
	if dive_bomb_controller != null and dive_bomb_controller.is_active():
		dive_bomb_controller.update_dive(delta)
		if dive_bomb_controller.state \
				== DiveBombAttackController.State.PULLING_OUT:
			manual_dive_state = ManualDiveCommandState.PULLING_OUT
		_update_selection_indicator()
		return
	if manual_dive_state == ManualDiveCommandState.PULLING_OUT \
			and dive_bomb_controller != null \
			and dive_bomb_controller.state \
				== DiveBombAttackController.State.COMPLETED:
		manual_dive_state = ManualDiveCommandState.READY \
			if has_any_ammunition() else ManualDiveCommandState.NONE
		if manual_return_after_release:
			request_return()
			return
	match state:
		State.EN_ROUTE:
			_advance_formation_center(destination, delta)
			if _has_formation_arrived(destination):
				state = State.HOLDING
		State.HOLDING:
			formation_center.y = move_toward(
				formation_center.y,
				destination.y,
				_get_aircraft_speed() * 0.35 * delta
			)
		State.RETURNING:
			var carrier := get_owner_carrier()
			if carrier == null:
				_mark_destroyed()
				return
			var recovery_position := _get_carrier_recovery_position()
			_advance_formation_center(recovery_position, delta)
			if _has_formation_arrived(recovery_position):
				_complete_recovery()
				return
		State.RECOVERING, State.DESTROYED:
			return
	_update_aircraft_formation_targets()
	_update_selection_indicator()


func _update_weapon_release_sequence(delta: float) -> void:
	if _release_queue.is_empty():
		return
	_release_interval_left = maxf(0.0, _release_interval_left - delta)
	if _release_interval_left > 0.0:
		return
	while not _release_queue.is_empty():
		var aircraft_value: Variant = _release_queue.pop_front()
		var aircraft := aircraft_value as AircraftUnit
		if not is_instance_valid(aircraft) or not aircraft.is_alive() \
				or aircraft.weapon_controller == null:
			continue
		if aircraft.weapon_controller.release(
			_release_target_position,
			_release_target_velocity
		):
			var data: AircraftWeaponData = \
				aircraft.weapon_controller.weapon_data
			_release_interval_left = maxf(
				data.release_interval_sec if data != null else 0.0,
				0.0
			)
			return


func _spawn_aircraft() -> void:
	var data := squadron_data.aircraft_data
	if data.aircraft_scene == null:
		return
	var count := _requested_aircraft_count \
		if _requested_aircraft_count >= 0 \
		else squadron_data.aircraft_count
	count = clampi(count, 0, maxi(squadron_data.aircraft_count, 0))
	for index in range(count):
		var aircraft := data.aircraft_scene.instantiate() as AircraftUnit
		if aircraft == null:
			continue
		add_child(aircraft)
		var offset := _calculate_formation_offset(index, count)
		aircraft.global_position = formation_center + offset * 0.15
		aircraft.setup(data, get_owner_carrier().team, offset)
		aircraft.deactivate()
		if not aircraft.destroyed.is_connected(_on_aircraft_destroyed):
			aircraft.destroyed.connect(_on_aircraft_destroyed)
		aircraft_units.append(aircraft)


func _calculate_formation_offset(index: int, count: int) -> Vector3:
	var spacing := maxf(squadron_data.formation_spacing_m, 1.0)
	var center_index := float(count - 1) * 0.5
	var lateral := (float(index) - center_index) * spacing
	var depth := absf(float(index) - center_index) * spacing * 0.35
	return Vector3(lateral, 0.0, depth)


func _update_launch_sequence(delta: float) -> void:
	if _next_aircraft_to_activate >= aircraft_units.size():
		return
	_launch_elapsed_sec += delta
	var interval := maxf(squadron_data.launch_interval_sec, 0.0)
	if interval <= 0.0 or _launch_elapsed_sec >= interval:
		_launch_elapsed_sec = 0.0
		_activate_next_aircraft()


func _activate_next_aircraft() -> void:
	while _next_aircraft_to_activate < aircraft_units.size():
		var aircraft := aircraft_units[_next_aircraft_to_activate]
		_next_aircraft_to_activate += 1
		if is_instance_valid(aircraft):
			aircraft.activate()
			if _next_aircraft_to_activate >= aircraft_units.size() \
					and not _formation_activated_emitted:
				_formation_activated_emitted = true
				formation_activated.emit(self)
			return


func _advance_formation_center(target: Vector3, delta: float) -> void:
	var horizontal_offset := Vector3(
		target.x - formation_center.x,
		0.0,
		target.z - formation_center.z
	)
	if horizontal_offset.length_squared() > EPSILON:
		var desired_forward := horizontal_offset.normalized()
		var turn_step := deg_to_rad(
			maxf(squadron_data.aircraft_data.turn_rate_deg_sec, 0.0)
		) * delta
		var angle := _formation_forward.angle_to(desired_forward)
		var weight := minf(1.0, turn_step / maxf(angle, EPSILON))
		_formation_forward = _formation_forward.slerp(
			desired_forward,
			weight
		).normalized()
		var travel_distance := minf(
			_get_aircraft_speed() * delta,
			horizontal_offset.length()
		)
		formation_center += _formation_forward * travel_distance
	formation_center.y = move_toward(
		formation_center.y,
		target.y,
		_get_aircraft_speed() * 0.35 * delta
	)


func apply_direct_flight(
		direction: Vector3,
		speed_mps: float,
		delta: float,
		minimum_world_y: float
) -> void:
	if direction.length_squared() <= EPSILON:
		return
	_formation_forward = direction.normalized()
	formation_center += _formation_forward \
		* maxf(speed_mps, 0.0) * maxf(delta, 0.0)
	formation_center.y = maxf(formation_center.y, minimum_world_y)
	for aircraft in get_alive_aircraft():
		aircraft.set_direct_flight(_formation_forward, speed_mps)


func finish_direct_flight_holding(world_altitude: float) -> void:
	formation_center.y = world_altitude
	destination = formation_center
	state = State.HOLDING
	for aircraft in get_alive_aircraft():
		aircraft.set_formation_flight()
	_update_aircraft_formation_targets()


func restore_formation_flight() -> void:
	for aircraft in get_alive_aircraft():
		aircraft.set_formation_flight()
	_update_aircraft_formation_targets()


func get_average_alive_aircraft_position() -> Vector3:
	var aircraft := get_alive_aircraft()
	if aircraft.is_empty():
		return formation_center
	var total := Vector3.ZERO
	for unit in aircraft:
		total += unit.global_position
	return total / float(aircraft.size())


func get_average_alive_aircraft_altitude() -> float:
	return get_average_alive_aircraft_position().y


func is_formation_aligned(
		maximum_error_m: float
) -> bool:
	var errors := get_formation_alignment_errors()
	if errors.is_empty():
		return false
	var allowed_error := maxf(maximum_error_m, 0.0)
	for error in errors:
		if error > allowed_error:
			return false
	return true


func get_formation_alignment_errors() -> PackedFloat32Array:
	var alive_aircraft := get_alive_aircraft()
	var result := PackedFloat32Array()
	if alive_aircraft.is_empty():
		return result
	var right := _formation_forward.cross(Vector3.UP).normalized()
	if right.length_squared() <= EPSILON:
		right = Vector3.RIGHT
	var offset_multiplier := 0.8 if _combat_formation_enabled else 1.0
	for aircraft in alive_aircraft:
		var offset := aircraft.formation_offset * offset_multiplier
		var expected_position := formation_center \
			+ right * offset.x \
			+ Vector3.UP * offset.y \
			+ _formation_forward * offset.z
		result.append(aircraft.global_position.distance_to(expected_position))
	return result


func _update_aircraft_formation_targets() -> void:
	var right := _formation_forward.cross(Vector3.UP).normalized()
	if right.length_squared() <= EPSILON:
		right = Vector3.RIGHT
	for aircraft in aircraft_units:
		if not is_instance_valid(aircraft) or not aircraft.active:
			continue
		var offset_multiplier := 0.8 if _combat_formation_enabled else 1.0
		var offset := aircraft.formation_offset * offset_multiplier
		var world_offset := right * offset.x \
			+ Vector3.UP * offset.y \
			+ _formation_forward * offset.z
		aircraft.set_formation_target(formation_center + world_offset)


func _update_selection_indicator() -> void:
	if selection_indicator == null:
		return
	selection_indicator.global_position = formation_center \
		+ Vector3.DOWN * 8.0


func _has_formation_arrived(target: Vector3) -> bool:
	var data := squadron_data.aircraft_data
	var horizontal_distance := Vector2(
		target.x - formation_center.x,
		target.z - formation_center.z
	).length()
	return horizontal_distance <= maxf(data.arrival_distance_m, 1.0) \
		and absf(target.y - formation_center.y) \
			<= maxf(data.arrival_distance_m, 1.0)


func _get_aircraft_speed() -> float:
	var data := squadron_data.aircraft_data
	return minf(
		maxf(data.cruise_speed_mps, 0.0),
		maxf(data.maximum_speed_mps, 0.0)
	)


func _clamp_destination_to_combat_radius(
		world_position: Vector3
) -> Vector3:
	var carrier := get_owner_carrier()
	var data := squadron_data.aircraft_data
	var result := world_position
	var origin := carrier.global_position
	var horizontal := Vector2(
		world_position.x - origin.x,
		world_position.z - origin.z
	)
	var radius := maxf(data.combat_radius_m, 0.0)
	if radius > 0.0 and horizontal.length() > radius:
		horizontal = horizontal.normalized() * radius
		result.x = origin.x + horizontal.x
		result.z = origin.z + horizontal.y
	result.y = maxf(
		world_position.y,
		carrier.global_position.y + data.operating_altitude_m
	)
	return result


func _clamp_destination_horizontal(world_position: Vector3) -> Vector3:
	var carrier := get_owner_carrier()
	var data := squadron_data.aircraft_data
	if carrier == null or data == null:
		return world_position
	var result := world_position
	var horizontal := Vector2(
		world_position.x - carrier.global_position.x,
		world_position.z - carrier.global_position.z
	)
	var radius := maxf(data.combat_radius_m, 0.0)
	if radius > 0.0 and horizontal.length() > radius:
		horizontal = horizontal.normalized() * radius
		result.x = carrier.global_position.x + horizontal.x
		result.z = carrier.global_position.z + horizontal.y
	return result


func get_command_debug_snapshot() -> Dictionary:
	var attack_target := get_manual_attack_target()
	return {
		"command_authority": CommandAuthority.keys()[int(command_authority)],
		"manual_move_target": _manual_move_target,
		"has_manual_move_target": _has_manual_move_target,
		"manual_attack_target":
			attack_target.name if attack_target != null else "",
		"manual_dive_state":
			ManualDiveCommandState.keys()[int(manual_dive_state)],
	}


func _can_accept_player_command() -> bool:
	var carrier := get_owner_carrier()
	return carrier != null \
		and is_instance_valid(carrier) \
		and carrier.player_controlled \
		and get_team() == FactionRelations.PLAYER \
		and get_alive_aircraft_count() > 0 \
		and state not in [
			State.RETURNING,
			State.RECOVERING,
			State.DESTROYED,
		]


func _is_valid_manual_attack_target(target: ShipUnit) -> bool:
	var carrier := get_owner_carrier()
	return target != null \
		and is_instance_valid(target) \
		and not target.is_queued_for_deletion() \
		and target.is_alive() \
		and carrier != null \
		and carrier.is_hostile_to(target)


func _get_carrier_launch_position() -> Vector3:
	var carrier := get_owner_carrier()
	var air_group := carrier.carrier_air_group
	if air_group == null or air_group.air_group_data == null:
		return carrier.global_position
	return carrier.global_transform * air_group.air_group_data.launch_local_position


func _get_carrier_recovery_position() -> Vector3:
	var carrier := get_owner_carrier()
	var air_group := carrier.carrier_air_group
	if air_group == null or air_group.air_group_data == null:
		return carrier.global_position
	return carrier.global_transform \
		* air_group.air_group_data.recovery_local_position


func _complete_recovery() -> void:
	if _completion_emitted:
		return
	_completion_emitted = true
	set_player_selected(false)
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_squadron(self)
	state = State.RECOVERING
	set_physics_process(false)
	for aircraft in aircraft_units:
		if is_instance_valid(aircraft):
			aircraft.deactivate()
	recovery_completed.emit(self)


func _mark_destroyed() -> void:
	if _completion_emitted:
		return
	_completion_emitted = true
	set_player_selected(false)
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_squadron(self)
	state = State.DESTROYED
	set_physics_process(false)
	if not squadron_lost.get_connections().is_empty():
		squadron_lost.emit(self)
		return
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").squadron_destroyed.emit(self)
	release_aircraft()
	queue_free()


func _on_aircraft_destroyed(aircraft: AircraftUnit) -> void:
	if aircraft == null:
		return
	aircraft_lost.emit(self, aircraft)
	call_deferred(&"_check_after_aircraft_loss")


func _check_after_aircraft_loss() -> void:
	_prune_aircraft()
	if get_alive_aircraft_count() > 0:
		return
	if mission_controller != null \
			and mission_controller.has_method(&"fail_without_return"):
		mission_controller.call(&"fail_without_return")
	_mark_destroyed()


func _prune_aircraft() -> void:
	for index in range(aircraft_units.size() - 1, -1, -1):
		if not is_instance_valid(aircraft_units[index]):
			aircraft_units.remove_at(index)


func _exit_tree() -> void:
	if is_in_group(&"aircraft_squadrons"):
		remove_from_group(&"aircraft_squadrons")
	var coordinator := get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_squadron(self)
