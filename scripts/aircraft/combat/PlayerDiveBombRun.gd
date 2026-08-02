extends RefCounted
class_name PlayerDiveBombRun

# Drives a player-ordered dive bomb on a chosen world point. Unlike the AI
# mission (which targets a ship), this flies the squadron to a dive-entry point
# above and short of the clicked location, then hands off to the dive bomb
# controller so the run descends into the target and releases there — instead of
# dropping from the squadron's current position. The dispersion radius from the
# accuracy preview is passed straight through to the controller.

enum State {
	MOVING_TO_ENTRY,
	DIVING,
	DONE,
}

const EPSILON := 0.0001

var state: State = State.DONE

var _squadron: AircraftSquadron
var _target_point := Vector3.ZERO
var _dispersion_radius_m := 0.0
var _destination_initialized := false
var _active_destination_serial := -1


func setup(
		squadron: AircraftSquadron,
		target_point: Vector3,
		dispersion_radius_m: float
) -> bool:
	_squadron = squadron
	_target_point = target_point
	_dispersion_radius_m = maxf(dispersion_radius_m, 0.0)
	if _squadron == null or not is_instance_valid(_squadron) \
			or _squadron.dive_bomb_controller == null \
			or _get_dive_data() == null:
		state = State.DONE
		return false
	state = State.MOVING_TO_ENTRY
	_destination_initialized = false
	_active_destination_serial = -1
	return true


func update(_delta: float) -> void:
	if is_finished() or _squadron == null or not is_instance_valid(_squadron):
		state = State.DONE
		return
	if state == State.MOVING_TO_ENTRY:
		_update_move_to_entry()


func is_finished() -> bool:
	return state == State.DIVING or state == State.DONE


func cancel(_reason: StringName = &"") -> void:
	state = State.DONE


func _update_move_to_entry() -> void:
	var entry_position := _calculate_dive_entry_position()
	if not _destination_initialized:
		_active_destination_serial = _squadron.set_mission_destination(
			entry_position,
			true
		)
		_destination_initialized = true
	if not _squadron.has_reached_mission_destination(
		_active_destination_serial
	):
		return
	var controller := _squadron.dive_bomb_controller
	if controller == null:
		state = State.DONE
		return
	var begin_result := controller.begin_dive_with_source(
		_target_point,
		Vector3.ZERO,
		AircraftSquadron.DiveControlSource.PLAYER,
		_dispersion_radius_m
	)
	if begin_result == DiveBombAttackController.BeginDiveResult.STARTED \
			or begin_result == DiveBombAttackController.BeginDiveResult \
				.ALREADY_ACTIVE_SAME_SOURCE:
		state = State.DIVING
	else:
		state = State.DONE


func _attack_direction() -> Vector3:
	var carrier := _squadron.get_owner_carrier()
	var origin := carrier.global_position \
		if carrier != null else _squadron.formation_center
	var direction := _target_point - origin
	direction.y = 0.0
	if direction.length_squared() <= EPSILON:
		direction = _squadron.get_formation_forward()
		direction.y = 0.0
	return direction.normalized() \
		if direction.length_squared() > EPSILON else Vector3.FORWARD


func _calculate_dive_entry_position() -> Vector3:
	var dive_data := _get_dive_data()
	var height := maxf(dive_data.dive_entry_altitude_m, 1.0)
	var tangent := tan(deg_to_rad(clampf(
		dive_data.dive_angle_degrees,
		1.0,
		89.0
	)))
	var horizontal_distance := (
		dive_data.dive_entry_horizontal_distance_m
		if dive_data.dive_entry_horizontal_distance_m > 0.0
		else height / maxf(tangent, 0.01)
	)
	var result := _target_point - _attack_direction() * horizontal_distance
	result.y = _target_point.y + height
	return result


func _get_dive_data() -> DiveBomberCombatData:
	return _squadron.get_dive_bomber_combat_data() \
		if _squadron != null and is_instance_valid(_squadron) else null
