extends RefCounted
class_name DiveBombMissionBehavior

enum State {
	APPROACHING,
	DIVE_ENTRY,
	DIVING,
	RELEASING,
	PULLING_OUT,
	EGRESS,
	RETURNING,
	COMPLETED,
	FAILED,
}

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var mission_data: AirMissionData
var state: State = State.FAILED
var successful := false

var _target_ref: WeakRef
var _finished := true
var _destination_initialized := false
var _bombs_released := false


func setup(
		next_owner_squadron: AircraftSquadron,
		target_ship: Node3D,
		next_mission_data: AirMissionData
) -> bool:
	owner_squadron = next_owner_squadron
	mission_data = next_mission_data
	if not _is_valid_setup(target_ship):
		return false
	_target_ref = weakref(target_ship)
	state = State.APPROACHING
	successful = false
	_finished = false
	_destination_initialized = false
	_bombs_released = false
	return true


func update(_delta: float) -> void:
	if _finished or owner_squadron == null \
			or not is_instance_valid(owner_squadron):
		return
	var target := _get_target_ship()
	if target == null:
		_finish_and_return(false)
		return
	match state:
		State.APPROACHING:
			_update_approaching(target)
		State.DIVE_ENTRY:
			_update_dive_entry(target)
		State.DIVING:
			_update_diving(target)
		State.RELEASING:
			state = State.PULLING_OUT
		State.PULLING_OUT:
			_update_pulling_out(target)
		State.EGRESS:
			_update_egress()
		State.RETURNING, State.COMPLETED, State.FAILED:
			pass


func cancel_and_return() -> void:
	if _finished:
		return
	_cancel_dive()
	_finish_and_return(false)


func cancel_without_return() -> void:
	if _finished:
		return
	_cancel_dive()
	successful = false
	_finished = true
	state = State.FAILED
	_target_ref = null


func get_state() -> int:
	return int(state)


func is_finished() -> bool:
	return _finished


func get_target_ship() -> Node3D:
	return _get_target_ship()


func _update_approaching(target: Node3D) -> void:
	var approach_position := _calculate_approach_position(target)
	if not _destination_initialized:
		owner_squadron.set_mission_destination(approach_position)
		_destination_initialized = true
	if owner_squadron.state != AircraftSquadron.State.HOLDING:
		return
	state = State.DIVE_ENTRY
	_destination_initialized = false


func _update_dive_entry(target: Node3D) -> void:
	var entry_position := _calculate_dive_entry_position(target)
	if not _destination_initialized:
		owner_squadron.set_mission_destination(entry_position)
		_destination_initialized = true
	if owner_squadron.state != AircraftSquadron.State.HOLDING:
		return
	var controller := owner_squadron.dive_bomb_controller
	if controller == null:
		return
	var predicted_position := _calculate_predicted_target_position(target)
	if not controller.begin_dive(
		predicted_position,
		_get_target_velocity(target)
	):
		_finish_and_return(false)
		return
	state = State.DIVING


func _update_diving(target: Node3D) -> void:
	var controller := owner_squadron.dive_bomb_controller
	if controller == null:
		_finish_and_return(false)
		return
	var predicted_position := _calculate_predicted_target_position(target)
	controller.update_target(
		predicted_position,
		_get_target_velocity(target)
	)
	if controller.state == DiveBombAttackController.State.PULLING_OUT:
		state = State.PULLING_OUT
		return
	if _is_target_inside_release_window(predicted_position):
		var released_count := controller.release_ready_bombs()
		if released_count > 0:
			_bombs_released = true
	if controller.should_force_pull_out():
		controller.begin_pull_out()
		state = State.PULLING_OUT


func _update_pulling_out(target: Node3D) -> void:
	var controller := owner_squadron.dive_bomb_controller
	if controller == null:
		_finish_and_return(false)
		return
	if controller.state == DiveBombAttackController.State.FAILED:
		_finish_and_return(false)
		return
	if controller.state != DiveBombAttackController.State.COMPLETED:
		return
	if not _bombs_released:
		_finish_and_return(false)
		return
	var direction := owner_squadron.get_formation_forward()
	direction.y = 0.0
	if direction.length_squared() <= EPSILON:
		direction = target.global_position - owner_squadron.formation_center
		direction.y = 0.0
	direction = direction.normalized() \
		if direction.length_squared() > EPSILON else Vector3.FORWARD
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	var distance := weapon_data.attack_egress_distance_m \
		if weapon_data != null else 700.0
	var destination := owner_squadron.formation_center \
		+ direction * maxf(distance, 0.0)
	destination.y = _get_operating_world_altitude()
	owner_squadron.set_mission_destination(destination)
	state = State.EGRESS


func _update_egress() -> void:
	if owner_squadron.state != AircraftSquadron.State.HOLDING:
		return
	successful = true
	_finished = true
	state = State.COMPLETED
	_target_ref = null
	if mission_data == null or mission_data.return_after_attack:
		state = State.RETURNING
		owner_squadron.request_return()


func _finish_and_return(was_successful: bool) -> void:
	if _finished:
		return
	_cancel_dive()
	successful = was_successful
	_finished = true
	state = State.COMPLETED if was_successful else State.FAILED
	_target_ref = null
	if owner_squadron != null and is_instance_valid(owner_squadron):
		state = State.RETURNING
		owner_squadron.request_return()


func _cancel_dive() -> void:
	if owner_squadron != null \
			and is_instance_valid(owner_squadron) \
			and owner_squadron.dive_bomb_controller != null:
		owner_squadron.dive_bomb_controller.cancel()


func _calculate_approach_position(target: Node3D) -> Vector3:
	var direction := _get_attack_direction(target)
	var dive_data := _get_dive_data()
	var result := target.global_position \
		- direction * maxf(dive_data.approach_distance_m, 0.0)
	result.y = target.global_position.y \
		+ maxf(dive_data.dive_entry_altitude_m, 1.0)
	return result


func _calculate_dive_entry_position(target: Node3D) -> Vector3:
	var dive_data := _get_dive_data()
	var height := maxf(dive_data.dive_entry_altitude_m, 1.0)
	var tangent := tan(deg_to_rad(clampf(
		dive_data.dive_angle_degrees,
		1.0,
		89.0
	)))
	var horizontal_distance := (
		dive_data.dive_entry_horizontal_distance_m
		if dive_data.dive_entry_horizontal_distance_m > 0.0 \
		else height / maxf(tangent, 0.01)
	)
	var predicted := _calculate_predicted_target_position(target)
	var result := predicted \
		- _get_attack_direction(target) * horizontal_distance
	result.y = target.global_position.y + height
	return result


func _calculate_predicted_target_position(target: Node3D) -> Vector3:
	if mission_data == null or not mission_data.target_prediction_enabled:
		return target.global_position
	var height := maxf(
		owner_squadron.formation_center.y - target.global_position.y,
		1.0
	)
	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var fall_time := sqrt(2.0 * height / maxf(gravity, 0.1))
	return target.global_position + _get_target_velocity(target) * fall_time


func _is_target_inside_release_window(
		predicted_position: Vector3
) -> bool:
	var dive_data := _get_dive_data()
	var offset := predicted_position - owner_squadron.formation_center
	var horizontal_distance := Vector2(offset.x, offset.z).length()
	if horizontal_distance \
			> maxf(dive_data.automatic_release_distance_m, 0.0):
		return false
	if offset.length_squared() <= EPSILON:
		return true
	var minimum_dot := cos(deg_to_rad(
		clampf(dive_data.maximum_dive_target_angle_degrees, 0.0, 89.0)
	))
	return owner_squadron.get_formation_forward().dot(
		offset.normalized()
	) >= minimum_dot


func _get_attack_direction(target: Node3D) -> Vector3:
	var carrier := owner_squadron.get_owner_carrier()
	var origin := carrier.global_position \
		if carrier != null else owner_squadron.formation_center
	var direction := target.global_position - origin
	direction.y = 0.0
	return direction.normalized() \
		if direction.length_squared() > EPSILON else Vector3.FORWARD


func _get_target_velocity(target: Node3D) -> Vector3:
	var body := target as CharacterBody3D
	return body.velocity if body != null else Vector3.ZERO


func _get_operating_world_altitude() -> float:
	var carrier := owner_squadron.get_owner_carrier()
	var base_height := carrier.global_position.y if carrier != null else 0.0
	return base_height \
		+ owner_squadron.squadron_data.aircraft_data.operating_altitude_m


func _get_dive_data() -> DiveBomberCombatData:
	return owner_squadron.squadron_data.aircraft_data \
		.dive_bomber_combat_data


func _get_target_ship() -> Node3D:
	if _target_ref == null:
		return null
	var target := _target_ref.get_ref() as Node3D
	if target == null or not is_instance_valid(target) \
			or target.is_queued_for_deletion():
		return null
	if target.has_method(&"is_alive") and not bool(target.call(&"is_alive")):
		return null
	return target


func _is_valid_setup(target: Node3D) -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.DIVE_BOMBER \
		and owner_squadron.dive_bomb_controller != null \
		and _get_dive_data() != null \
		and _get_dive_data().validate().is_empty() \
		and target != null \
		and is_instance_valid(target) \
		and mission_data != null \
		and mission_data.mission_type \
			== AirMissionData.MissionType.STRIKE_SHIP
