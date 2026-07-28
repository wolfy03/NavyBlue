extends Node
class_name DiveBombAttackController

enum State {
	IDLE,
	DIVE_ENTRY,
	DIVING,
	RELEASE_READY,
	BOMB_RELEASED,
	PULLING_OUT,
	COMPLETED,
	FAILED,
}

enum ReleaseBlockReason {
	NONE,
	TOO_EARLY,
	ALTITUDE_TOO_HIGH,
	ALTITUDE_TOO_LOW,
	NO_AMMUNITION,
	NOT_DIVING,
	WEAPON_DISABLED,
}

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var dive_data: DiveBomberCombatData
var state: State = State.IDLE
var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
var dive_elapsed_seconds := 0.0
var release_block_reason: ReleaseBlockReason = ReleaseBlockReason.NOT_DIVING

var _pull_out_forward := Vector3.FORWARD


func setup(squadron: AircraftSquadron) -> void:
	owner_squadron = squadron
	dive_data = squadron.squadron_data.aircraft_data \
		.dive_bomber_combat_data \
		if squadron != null \
		and squadron.squadron_data != null \
		and squadron.squadron_data.aircraft_data != null else null
	reset()


func reset() -> void:
	state = State.IDLE
	target_position = Vector3.ZERO
	target_velocity = Vector3.ZERO
	dive_elapsed_seconds = 0.0
	release_block_reason = ReleaseBlockReason.NOT_DIVING
	_pull_out_forward = Vector3.FORWARD


func begin_dive(
		next_target_position: Vector3,
		next_target_velocity: Vector3 = Vector3.ZERO
) -> bool:
	if not _is_valid_dive_squadron() \
			or is_active() \
			or not owner_squadron.has_any_ammunition():
		return false
	target_position = next_target_position
	target_velocity = next_target_velocity
	dive_elapsed_seconds = 0.0
	release_block_reason = ReleaseBlockReason.TOO_EARLY
	state = State.DIVE_ENTRY
	return true


func update_target(
		next_target_position: Vector3,
		next_target_velocity: Vector3
) -> void:
	if not is_active():
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
		State.DIVING, State.RELEASE_READY:
			_update_diving(delta)
		State.BOMB_RELEASED:
			begin_pull_out()
		State.PULLING_OUT:
			_update_pull_out(delta)
		State.IDLE, State.COMPLETED, State.FAILED:
			pass


func can_release_bombs() -> bool:
	release_block_reason = _get_release_block_reason()
	return release_block_reason == ReleaseBlockReason.NONE


func release_bombs() -> int:
	if not can_release_bombs():
		return 0
	var released_count := owner_squadron.request_weapon_release(
		target_position,
		target_velocity
	)
	if released_count <= 0:
		release_block_reason = ReleaseBlockReason.WEAPON_DISABLED
		return 0
	state = State.BOMB_RELEASED
	begin_pull_out()
	return released_count


func begin_pull_out() -> void:
	if state in [State.IDLE, State.COMPLETED, State.FAILED]:
		return
	_pull_out_forward = owner_squadron.get_formation_forward()
	_pull_out_forward.y = 0.0
	if _pull_out_forward.length_squared() <= EPSILON:
		_pull_out_forward = Vector3.FORWARD
	else:
		_pull_out_forward = _pull_out_forward.normalized()
	state = State.PULLING_OUT


func cancel() -> void:
	if state == State.IDLE:
		return
	state = State.FAILED
	release_block_reason = ReleaseBlockReason.NOT_DIVING


func get_state() -> int:
	return int(state)


func is_active() -> bool:
	return state in [
		State.DIVE_ENTRY,
		State.DIVING,
		State.RELEASE_READY,
		State.BOMB_RELEASED,
		State.PULLING_OUT,
	]


func get_debug_snapshot() -> Dictionary:
	return {
		"state": State.keys()[int(state)],
		"target_position": target_position,
		"current_altitude": _get_current_altitude(),
		"dive_elapsed_time": dive_elapsed_seconds,
		"release_allowed": can_release_bombs(),
		"release_block_reason":
			ReleaseBlockReason.keys()[int(release_block_reason)],
		"remaining_ammunition":
			owner_squadron.get_total_remaining_ammunition() \
			if owner_squadron != null \
			and is_instance_valid(owner_squadron) else 0,
	}


func _update_diving(delta: float) -> void:
	dive_elapsed_seconds += maxf(delta, 0.0)
	target_position += target_velocity * maxf(delta, 0.0)
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
	if _get_current_altitude() <= dive_data.automatic_pull_out_altitude_m:
		begin_pull_out()
		return
	release_block_reason = _get_release_block_reason()
	state = State.RELEASE_READY \
		if release_block_reason == ReleaseBlockReason.NONE \
		else State.DIVING


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
		state = State.COMPLETED


func _get_release_block_reason() -> ReleaseBlockReason:
	if state not in [State.DIVING, State.RELEASE_READY]:
		return ReleaseBlockReason.NOT_DIVING
	if dive_elapsed_seconds \
			< maxf(dive_data.minimum_dive_time_before_release_sec, 0.0):
		return ReleaseBlockReason.TOO_EARLY
	if not owner_squadron.has_any_ammunition():
		return ReleaseBlockReason.NO_AMMUNITION
	var altitude := _get_current_altitude()
	if altitude > dive_data.maximum_release_altitude_m:
		return ReleaseBlockReason.ALTITUDE_TOO_HIGH
	if altitude < dive_data.minimum_release_altitude_m:
		return ReleaseBlockReason.ALTITUDE_TOO_LOW
	if not owner_squadron.can_release_payload():
		return ReleaseBlockReason.WEAPON_DISABLED
	return ReleaseBlockReason.NONE


func _get_current_altitude() -> float:
	return owner_squadron.formation_center.y - target_position.y \
		if owner_squadron != null \
		and is_instance_valid(owner_squadron) else 0.0


func _is_valid_dive_squadron() -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.DIVE_BOMBER \
		and dive_data != null \
		and dive_data.validate().is_empty()
