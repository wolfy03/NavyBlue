extends Node
class_name DiveBombAttackController

signal automatic_release_completed(released_count: int)
signal automatic_release_failed(reason: ReleaseBlockReason)

enum State {
	IDLE,
	DIVE_ENTRY,
	DIVING,
	RELEASING,
	PULLING_OUT,
	COMPLETED,
	FAILED,
}

enum ReleaseBlockReason {
	NONE,
	TOO_EARLY,
	NO_AMMUNITION,
	WEAPON_DISABLED,
	RELEASE_SEQUENCE_IN_PROGRESS,
	NO_RELEASE_CAPABLE_AIRCRAFT,
	SAFETY_ALTITUDE_REACHED,
}

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var dive_data: DiveBomberCombatData
var state: State = State.IDLE
var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
var dive_elapsed_seconds := 0.0
var release_block_reason: ReleaseBlockReason = ReleaseBlockReason.NONE

var _pull_out_forward := Vector3.FORWARD
var _release_started := false
var _release_failed := false
var _release_sequence_completed := false
var _ammunition_before_release := 0
var _previous_lowest_altitude := INF
var _any_bomb_released := false
var _release_sequence_queued_count_snapshot := 0
var _release_sequence_released_count_snapshot := 0


func setup(squadron: AircraftSquadron) -> void:
	owner_squadron = squadron
	dive_data = squadron.squadron_data.aircraft_data \
		.dive_bomber_combat_data \
		if squadron != null \
		and squadron.squadron_data != null \
		and squadron.squadron_data.aircraft_data != null else null
	if owner_squadron != null \
			and not owner_squadron.weapon_release_sequence_completed \
				.is_connected(_on_weapon_release_sequence_completed):
		owner_squadron.weapon_release_sequence_completed.connect(
			_on_weapon_release_sequence_completed
		)
	reset()


func reset() -> void:
	state = State.IDLE
	target_position = Vector3.ZERO
	target_velocity = Vector3.ZERO
	dive_elapsed_seconds = 0.0
	release_block_reason = ReleaseBlockReason.NONE
	_pull_out_forward = Vector3.FORWARD
	_release_started = false
	_release_failed = false
	_release_sequence_completed = false
	_ammunition_before_release = 0
	_previous_lowest_altitude = INF
	_any_bomb_released = false
	_release_sequence_queued_count_snapshot = 0
	_release_sequence_released_count_snapshot = 0


func begin_dive(
		next_target_position: Vector3,
		next_target_velocity: Vector3 = Vector3.ZERO
) -> bool:
	if not _is_valid_dive_squadron() \
			or state not in [State.IDLE, State.COMPLETED, State.FAILED] \
			or not owner_squadron.has_any_ammunition():
		return false
	if state in [State.COMPLETED, State.FAILED]:
		reset()
	target_position = next_target_position
	target_velocity = next_target_velocity
	dive_elapsed_seconds = 0.0
	release_block_reason = ReleaseBlockReason.TOO_EARLY
	_release_started = false
	_release_failed = false
	_release_sequence_completed = false
	_ammunition_before_release = \
		owner_squadron.get_total_remaining_ammunition()
	_previous_lowest_altitude = INF
	_any_bomb_released = false
	_release_sequence_queued_count_snapshot = 0
	_release_sequence_released_count_snapshot = 0
	state = State.DIVE_ENTRY
	return true


func update_target(
		next_target_position: Vector3,
		next_target_velocity: Vector3
) -> void:
	if state not in [State.DIVE_ENTRY, State.DIVING, State.RELEASING]:
		return
	target_position = next_target_position
	target_velocity = next_target_velocity


func update_dive(delta: float) -> void:
	if owner_squadron == null or not is_instance_valid(owner_squadron):
		state = State.FAILED
		return
	match state:
		State.DIVE_ENTRY:
			state = State.DIVING
		State.DIVING:
			_update_diving(delta)
		State.RELEASING:
			_update_releasing(delta)
		State.PULLING_OUT:
			_update_pull_out(delta)
		State.IDLE, State.COMPLETED, State.FAILED:
			pass


func begin_pull_out() -> void:
	if state in [
		State.IDLE,
		State.PULLING_OUT,
		State.COMPLETED,
		State.FAILED,
	]:
		return
	_pull_out_forward = owner_squadron.get_formation_forward()
	_pull_out_forward.y = 0.0
	if _pull_out_forward.length_squared() <= EPSILON:
		_pull_out_forward = Vector3.FORWARD
	else:
		_pull_out_forward = _pull_out_forward.normalized()
	state = State.PULLING_OUT


func cancel() -> void:
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.cancel_pending_weapon_release()
		owner_squadron.restore_formation_flight()
		owner_squadron.dive_control_source = \
			AircraftSquadron.DiveControlSource.NONE
	if state == State.COMPLETED:
		reset()
	elif state != State.IDLE:
		state = State.FAILED
		release_block_reason = ReleaseBlockReason.NONE


func get_state() -> int:
	return int(state)


func is_active() -> bool:
	return state in [
		State.DIVE_ENTRY,
		State.DIVING,
		State.RELEASING,
		State.PULLING_OUT,
	]


func did_release_any_bomb() -> bool:
	return _any_bomb_released


func get_release_block_reason() -> ReleaseBlockReason:
	return release_block_reason


func get_attack_result() -> Dictionary:
	return {
		"successful": _any_bomb_released,
		"release_started": _release_started,
		"release_failed": _release_failed,
		"released_count": _release_sequence_released_count_snapshot,
		"remaining_ammunition":
			owner_squadron.get_total_remaining_ammunition() \
			if owner_squadron != null \
			and is_instance_valid(owner_squadron) else 0,
		"final_state": State.keys()[int(state)],
	}


func get_lowest_alive_aircraft_altitude() -> float:
	if owner_squadron == null or not is_instance_valid(owner_squadron):
		return 0.0
	var lowest := INF
	for aircraft in owner_squadron.get_alive_aircraft():
		lowest = minf(lowest, aircraft.global_position.y - target_position.y)
	return lowest if lowest != INF else 0.0


func get_highest_alive_aircraft_altitude() -> float:
	if owner_squadron == null or not is_instance_valid(owner_squadron):
		return 0.0
	var highest := -INF
	for aircraft in owner_squadron.get_alive_aircraft():
		highest = maxf(
			highest,
			aircraft.global_position.y - target_position.y
		)
	return highest if highest != -INF else 0.0


func get_debug_snapshot() -> Dictionary:
	var control_source := "NONE"
	if owner_squadron != null and is_instance_valid(owner_squadron):
		control_source = AircraftSquadron.DiveControlSource.keys()[
			int(owner_squadron.dive_control_source)
		]
	return {
		"state": State.keys()[int(state)],
		"control_source": control_source,
		"target_position": target_position,
		"target_velocity": target_velocity,
		"lowest_aircraft_altitude":
			get_lowest_alive_aircraft_altitude(),
		"highest_aircraft_altitude":
			get_highest_alive_aircraft_altitude(),
		"automatic_release_altitude":
			dive_data.automatic_release_altitude_m \
			if dive_data != null else 0.0,
		"minimum_release_altitude":
			dive_data.minimum_release_altitude_m \
			if dive_data != null else 0.0,
		"automatic_pull_out_altitude":
			dive_data.automatic_pull_out_altitude_m \
			if dive_data != null else 0.0,
		"dive_elapsed_time": dive_elapsed_seconds,
		"release_started": _release_started,
		"release_sequence_active":
			owner_squadron.is_release_sequence_active() \
			if owner_squadron != null \
			and is_instance_valid(owner_squadron) else false,
		"queued_count": _release_sequence_queued_count_snapshot,
		"released_count": _release_sequence_released_count_snapshot,
		"remaining_ammunition":
			owner_squadron.get_total_remaining_ammunition() \
			if owner_squadron != null \
			and is_instance_valid(owner_squadron) else 0,
		"any_bomb_released": _any_bomb_released,
		"release_failure_reason":
			ReleaseBlockReason.keys()[int(release_block_reason)],
	}


func _update_diving(delta: float) -> void:
	dive_elapsed_seconds += maxf(delta, 0.0)
	_apply_dive_flight(delta)
	var lowest_altitude := get_lowest_alive_aircraft_altitude()
	if not _release_started \
			and dive_elapsed_seconds \
				>= maxf(
					dive_data.minimum_dive_time_before_release_sec,
					0.0
				) \
			and _has_crossed_automatic_release_altitude(
				lowest_altitude
			):
		_begin_automatic_release()
		_previous_lowest_altitude = lowest_altitude
		return
	if not _release_started \
			and lowest_altitude <= dive_data.minimum_release_altitude_m:
		_begin_automatic_release()
		_previous_lowest_altitude = lowest_altitude
		return
	if not _release_started \
			and lowest_altitude \
				<= dive_data.automatic_pull_out_altitude_m:
		_release_failed = true
		release_block_reason = \
			ReleaseBlockReason.SAFETY_ALTITUDE_REACHED
		automatic_release_failed.emit(release_block_reason)
		begin_pull_out()
		return
	_previous_lowest_altitude = lowest_altitude


func _update_releasing(delta: float) -> void:
	if owner_squadron.is_weapon_release_in_progress():
		if get_lowest_alive_aircraft_altitude() \
				<= dive_data.automatic_pull_out_altitude_m:
			_apply_release_safety_flight(delta)
		else:
			_apply_dive_flight(delta)
		return
	if not _release_sequence_completed:
		_release_sequence_completed = true
		_any_bomb_released = (
			owner_squadron.get_total_remaining_ammunition()
				< _ammunition_before_release
		)
		_release_failed = not _any_bomb_released
	if not _any_bomb_released:
		_release_failed = true
	begin_pull_out()


func _apply_dive_flight(delta: float) -> void:
	var to_target := target_position - owner_squadron.formation_center
	var horizontal_direction := Vector3(to_target.x, 0.0, to_target.z)
	if horizontal_direction.length_squared() <= EPSILON:
		horizontal_direction = owner_squadron.get_formation_forward()
		horizontal_direction.y = 0.0
	horizontal_direction = horizontal_direction.normalized() \
		if horizontal_direction.length_squared() > EPSILON \
		else Vector3.FORWARD
	var angle_rad := deg_to_rad(clampf(
		dive_data.dive_angle_degrees,
		1.0,
		89.0
	))
	var dive_direction := (
		horizontal_direction * cos(angle_rad)
		+ Vector3.DOWN * sin(angle_rad)
	).normalized()
	owner_squadron.apply_direct_flight(
		dive_direction,
		dive_data.dive_speed_mps,
		delta,
		target_position.y + maxf(
			dive_data.automatic_pull_out_altitude_m,
			0.0
		)
	)


func _apply_release_safety_flight(delta: float) -> void:
	var forward := owner_squadron.get_formation_forward()
	forward.y = 0.0
	forward = forward.normalized() \
		if forward.length_squared() > EPSILON else Vector3.FORWARD
	owner_squadron.apply_direct_flight(
		forward,
		dive_data.dive_speed_mps,
		delta,
		target_position.y + dive_data.automatic_pull_out_altitude_m
	)


func _update_pull_out(delta: float) -> void:
	var angle_rad := deg_to_rad(clampf(
		dive_data.pull_out_climb_angle_degrees,
		1.0,
		89.0
	))
	var climb_direction := (
		_pull_out_forward * cos(angle_rad)
		+ Vector3.UP * sin(angle_rad)
	).normalized()
	owner_squadron.apply_direct_flight(
		climb_direction,
		dive_data.dive_speed_mps,
		delta,
		target_position.y
	)
	var data := owner_squadron.squadron_data.aircraft_data
	var carrier := owner_squadron.get_owner_carrier()
	var desired_altitude := (
		carrier.global_position.y if carrier != null else target_position.y
	) + data.operating_altitude_m
	if owner_squadron.formation_center.y \
			>= desired_altitude - maxf(data.arrival_distance_m, 1.0):
		owner_squadron.finish_direct_flight_holding(desired_altitude)
		owner_squadron.dive_control_source = \
			AircraftSquadron.DiveControlSource.NONE
		state = State.COMPLETED


func _has_crossed_automatic_release_altitude(
		current_altitude: float
) -> bool:
	if _previous_lowest_altitude != INF \
			and current_altitude >= _previous_lowest_altitude:
		return false
	return current_altitude \
		<= dive_data.automatic_release_altitude_m \
			+ maxf(dive_data.release_altitude_tolerance_m, 0.0)


func _begin_automatic_release() -> void:
	if _release_started:
		return
	_release_started = true
	var queued_count := owner_squadron.request_weapon_release_for_dive(
		target_position,
		target_velocity
	)
	_release_sequence_queued_count_snapshot = queued_count
	if queued_count <= 0:
		_release_failed = true
		release_block_reason = _resolve_release_failure_reason()
		automatic_release_failed.emit(release_block_reason)
		begin_pull_out()
		return
	release_block_reason = ReleaseBlockReason.NONE
	state = State.RELEASING


func _resolve_release_failure_reason() -> ReleaseBlockReason:
	if owner_squadron.is_weapon_release_in_progress():
		return ReleaseBlockReason.RELEASE_SEQUENCE_IN_PROGRESS
	if not owner_squadron.has_any_ammunition():
		return ReleaseBlockReason.NO_AMMUNITION
	var has_weapon_controller := false
	for aircraft in owner_squadron.get_alive_aircraft():
		if aircraft.weapon_controller != null:
			has_weapon_controller = true
			if aircraft.weapon_controller.has_ammunition():
				return ReleaseBlockReason.WEAPON_DISABLED
	return (
		ReleaseBlockReason.WEAPON_DISABLED
		if has_weapon_controller
		else ReleaseBlockReason.NO_RELEASE_CAPABLE_AIRCRAFT
	)


func _on_weapon_release_sequence_completed(
		_queued_count: int,
		released_count: int
) -> void:
	if state != State.RELEASING or not _release_started:
		return
	_release_sequence_completed = true
	_release_sequence_released_count_snapshot = released_count
	_any_bomb_released = released_count > 0
	_release_failed = released_count <= 0
	if _any_bomb_released:
		automatic_release_completed.emit(released_count)
	else:
		release_block_reason = \
			ReleaseBlockReason.NO_RELEASE_CAPABLE_AIRCRAFT
		automatic_release_failed.emit(release_block_reason)


func _is_valid_dive_squadron() -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.DIVE_BOMBER \
		and dive_data != null \
		and dive_data.validate().is_empty()
