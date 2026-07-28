extends Node
class_name AircraftMissionController

signal mission_completed
signal mission_failed

enum MissionState {
	IDLE,
	APPROACHING,
	ATTACK_RUN,
	RELEASING,
	EGRESS,
	RETURNING,
	COMPLETED,
	FAILED,
}

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var mission_data: AirMissionData
var state: MissionState = MissionState.IDLE

var _target_ref: WeakRef
var _event_finished := false
var _approach_initialized := false
var _move_destination := Vector3.ZERO


func setup(next_owner_squadron: AircraftSquadron) -> void:
	owner_squadron = next_owner_squadron
	mission_data = null
	state = MissionState.IDLE
	_target_ref = null
	_event_finished = false
	_approach_initialized = false
	_move_destination = Vector3.ZERO


func assign_ship_strike(
		target_ship: Node3D,
		next_mission_data: AirMissionData
) -> bool:
	if owner_squadron == null \
			or not is_instance_valid(owner_squadron) \
			or not _is_valid_target(target_ship) \
			or next_mission_data == null \
			or next_mission_data.mission_type \
				!= AirMissionData.MissionType.STRIKE_SHIP:
		return false
	mission_data = next_mission_data
	_target_ref = weakref(target_ship)
	state = MissionState.APPROACHING
	_event_finished = false
	_approach_initialized = false
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").air_mission_started.emit(
			owner_squadron,
			target_ship
		)
	return true


func assign_move(
		world_position: Vector3,
		next_mission_data: AirMissionData
) -> bool:
	if owner_squadron == null \
			or not is_instance_valid(owner_squadron) \
			or next_mission_data == null \
			or next_mission_data.mission_type \
				!= AirMissionData.MissionType.MOVE:
		return false
	mission_data = next_mission_data
	_target_ref = null
	_move_destination = world_position
	state = MissionState.APPROACHING
	_event_finished = false
	_approach_initialized = false
	_emit_mission_started(null)
	return true


func assign_return(next_mission_data: AirMissionData) -> bool:
	if owner_squadron == null \
			or not is_instance_valid(owner_squadron) \
			or next_mission_data == null \
			or next_mission_data.mission_type \
				!= AirMissionData.MissionType.RETURN_TO_CARRIER:
		return false
	mission_data = next_mission_data
	_target_ref = null
	state = MissionState.RETURNING
	_event_finished = false
	_emit_mission_started(null)
	owner_squadron.request_return()
	return true


func update_mission(_delta: float) -> void:
	if state == MissionState.IDLE \
			or state == MissionState.COMPLETED \
			or state == MissionState.FAILED:
		return
	if mission_data != null \
			and mission_data.mission_type == AirMissionData.MissionType.MOVE:
		_update_move_mission()
		return
	if mission_data != null \
			and mission_data.mission_type \
				== AirMissionData.MissionType.RETURN_TO_CARRIER:
		return
	var target := get_target_ship()
	if target == null:
		_fail_and_return()
		return
	match state:
		MissionState.APPROACHING:
			_update_approach(target)
		MissionState.ATTACK_RUN:
			_update_attack_run(target)
		MissionState.RELEASING:
			if not owner_squadron.is_weapon_release_in_progress():
				_begin_egress(target)
		MissionState.EGRESS:
			if owner_squadron.state == AircraftSquadron.State.HOLDING:
				_complete_mission()
		MissionState.RETURNING:
			pass


func cancel_and_return() -> void:
	if state == MissionState.COMPLETED or state == MissionState.FAILED:
		return
	_fail_and_return()


func fail_without_return() -> void:
	if _event_finished:
		return
	_event_finished = true
	state = MissionState.FAILED
	mission_failed.emit()
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").air_mission_failed.emit(owner_squadron)


func cancel_mission_due_to_carrier_loss() -> void:
	fail_without_return()


func has_valid_target() -> bool:
	return get_target_ship() != null


func get_target_ship() -> Node3D:
	if _target_ref == null:
		return null
	var value: Variant = _target_ref.get_ref()
	var target := value as Node3D
	return target if _is_valid_target(target) else null


func _update_approach(target: Node3D) -> void:
	if not _approach_initialized:
		owner_squadron.set_mission_destination(
			_calculate_approach_position(target)
		)
		_approach_initialized = true
	if owner_squadron.state == AircraftSquadron.State.HOLDING:
		state = MissionState.ATTACK_RUN
		owner_squadron.set_mission_destination(
			_calculate_attack_position(target)
		)


func _update_attack_run(target: Node3D) -> void:
	var predicted_position := _calculate_predicted_target_position(target)
	owner_squadron.set_mission_destination(
		Vector3(
			predicted_position.x,
			target.global_position.y + _get_attack_altitude_m(),
			predicted_position.z
		)
	)
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	if weapon_data == null:
		_fail_and_return()
		return
	var horizontal_distance := _distance_xz(
		owner_squadron.formation_center,
		predicted_position
	)
	var altitude := owner_squadron.formation_center.y \
		- target.global_position.y
	if not weapon_data.supports_release(horizontal_distance, altitude):
		return
	var released_count := owner_squadron.request_weapon_release(
		predicted_position,
		_get_target_velocity(target)
	)
	if released_count > 0:
		state = MissionState.RELEASING
	elif not owner_squadron.has_any_ammunition():
		_begin_egress(target)


func _begin_egress(target: Node3D) -> void:
	state = MissionState.EGRESS
	var direction := owner_squadron.get_formation_forward()
	if direction.length_squared() <= EPSILON:
		direction = target.global_position - owner_squadron.formation_center
		direction.y = 0.0
		direction = direction.normalized() \
			if direction.length_squared() > EPSILON else Vector3.FORWARD
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	var egress_distance := weapon_data.attack_egress_distance_m \
		if weapon_data != null else 700.0
	var egress_position := target.global_position \
		+ direction * maxf(egress_distance, 0.0)
	egress_position.y = target.global_position.y + _get_attack_altitude_m()
	owner_squadron.set_mission_destination(egress_position)


func _complete_mission() -> void:
	if _event_finished:
		return
	_event_finished = true
	state = MissionState.COMPLETED
	mission_completed.emit()
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").air_mission_completed.emit(
			owner_squadron
		)
	if mission_data == null or mission_data.return_after_attack:
		state = MissionState.RETURNING
		owner_squadron.request_return()


func _update_move_mission() -> void:
	if not _approach_initialized:
		owner_squadron.set_mission_destination(_move_destination)
		_approach_initialized = true
	if owner_squadron.state != AircraftSquadron.State.HOLDING \
			or _event_finished:
		return
	_event_finished = true
	state = MissionState.COMPLETED
	mission_completed.emit()
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").air_mission_completed.emit(
			owner_squadron
		)


func _fail_and_return() -> void:
	if _event_finished:
		return
	_event_finished = true
	state = MissionState.FAILED
	mission_failed.emit()
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").air_mission_failed.emit(owner_squadron)
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.request_return()


func _emit_mission_started(target: Node3D) -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").air_mission_started.emit(
			owner_squadron,
			target
		)


func _calculate_approach_position(target: Node3D) -> Vector3:
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	var approach_distance := weapon_data.attack_approach_distance_m \
		if weapon_data != null else 1000.0
	var carrier := owner_squadron.get_owner_carrier()
	var approach_direction := target.global_position \
		- (
			carrier.global_position
			if carrier != null else owner_squadron.formation_center
		)
	approach_direction.y = 0.0
	if approach_direction.length_squared() <= EPSILON:
		approach_direction = Vector3.FORWARD
	else:
		approach_direction = approach_direction.normalized()
	var result := target.global_position \
		- approach_direction * maxf(approach_distance, 0.0)
	result.y = target.global_position.y + _get_attack_altitude_m()
	return result


func _calculate_attack_position(target: Node3D) -> Vector3:
	var predicted := _calculate_predicted_target_position(target)
	predicted.y = target.global_position.y + _get_attack_altitude_m()
	return predicted


func _calculate_predicted_target_position(target: Node3D) -> Vector3:
	if mission_data == null or not mission_data.target_prediction_enabled:
		return target.global_position
	var release_height := maxf(
		owner_squadron.formation_center.y - target.global_position.y,
		1.0
	)
	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var fall_time := sqrt(
		2.0 * release_height / maxf(gravity, 0.1)
	)
	return target.global_position + _get_target_velocity(target) * fall_time


func _get_attack_altitude_m() -> float:
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	if weapon_data == null:
		return maxf(mission_data.attack_altitude_m, 1.0)
	var requested_altitude := clampf(
		mission_data.attack_altitude_m,
		weapon_data.minimum_release_altitude_m,
		weapon_data.maximum_release_altitude_m
	)
	var horizontal_speed := maxf(
		owner_squadron.get_formation_velocity().length(),
		1.0
	)
	var flight_time_at_max_range := maxf(
		weapon_data.maximum_release_distance_m,
		0.0
	) / horizontal_speed
	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var reachable_height := maxf(
		weapon_data.downward_release_speed_mps * flight_time_at_max_range
			+ 0.5 * gravity * flight_time_at_max_range \
				* flight_time_at_max_range,
		weapon_data.minimum_release_altitude_m
	)
	return clampf(
		minf(requested_altitude, reachable_height),
		weapon_data.minimum_release_altitude_m,
		weapon_data.maximum_release_altitude_m
	)


func _get_target_velocity(target: Node3D) -> Vector3:
	var body := target as CharacterBody3D
	return body.velocity if body != null else Vector3.ZERO


func _is_valid_target(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target) \
			or target.is_queued_for_deletion():
		return false
	if target.has_method(&"is_alive"):
		return bool(target.call(&"is_alive"))
	return true


func _distance_xz(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()
