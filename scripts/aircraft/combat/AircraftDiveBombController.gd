extends RefCounted
class_name AircraftDiveBombController
## Executes one aircraft's already-solved dive. Target selection, accuracy and
## squadron aggregation deliberately live outside this class.

const EPSILON := 0.0001

var attack_state := DiveBombAircraftAttackState.new()
var weapon_data: AircraftWeaponData
var dive_data: DiveBomberCombatData
var attack_mode := DiveBombAttackMode.Type.NORMAL_APPROACH
var world_gravity_mps2 := 9.8
## Bumped on every setup and cancel. Any release outcome tagged with an older
## generation belongs to a previous attack and must not mutate this one.
var attack_generation := 0
## Generation of the aircraft's movement ownership at acquire time; if the
## aircraft's generation moves past this (forced override, re-acquire by
## another system), this controller's steering is stale.
var _owned_movement_generation := -1
var _movement_ownership_released := false


func setup(
		aircraft: AircraftUnit,
		next_weapon_data: AircraftWeaponData,
		next_dive_data: DiveBomberCombatData,
		solution: DiveBombAttackSolution,
		next_attack_mode: int = DiveBombAttackMode.Type.NORMAL_APPROACH
) -> bool:
	# Every validation runs BEFORE movement ownership is acquired, so a
	# rejected setup can never leave the aircraft owned by a dead controller.
	if not _validate_setup_inputs(
		aircraft,
		next_weapon_data,
		next_dive_data,
		solution
	):
		return false
	if not aircraft.acquire_movement_owner(
		AircraftMovementOwner.Type.DIVE_BOMB_ATTACK,
		&"dive_bomb_setup"
	):
		return false
	attack_generation += 1
	_owned_movement_generation = aircraft.movement_owner_generation
	_movement_ownership_released = false
	weapon_data = next_weapon_data
	dive_data = next_dive_data
	attack_mode = next_attack_mode
	world_gravity_mps2 = float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	attack_state = DiveBombAircraftAttackState.new()
	attack_state.aircraft_ref = weakref(aircraft)
	attack_state.aircraft_instance_id = aircraft.get_instance_id()
	attack_state.aircraft_combat_id = aircraft.aircraft_combat_id
	attack_state.aircraft_slot_id = aircraft.aircraft_slot_id
	attack_state.solution = solution.duplicate_solution()
	attack_state.locked_attack_direction = _flat_direction(
		solution.attack_direction
	)
	attack_state.locked_dive_direction = _build_locked_dive_direction(
		attack_state.locked_attack_direction
	)
	attack_state.state = DiveBombAircraftAttackState.State.APPROACHING \
		if attack_mode == DiveBombAttackMode.Type.NORMAL_APPROACH \
		else DiveBombAircraftAttackState.State.ALIGNING
	attack_state.release_block_reason = \
		DiveBombReleaseBlockReason.Type.TOO_EARLY
	return true


func _validate_setup_inputs(
		aircraft: AircraftUnit,
		next_weapon_data: AircraftWeaponData,
		next_dive_data: DiveBomberCombatData,
		solution: DiveBombAttackSolution
) -> bool:
	if aircraft == null or not is_instance_valid(aircraft) \
			or not aircraft.is_alive() or next_weapon_data == null \
			or next_dive_data == null or solution == null \
			or not solution.valid:
		return false
	if next_weapon_data.weapon_type != AircraftWeaponData.WeaponType.BOMB \
			or aircraft.weapon_controller == null \
			or not aircraft.weapon_controller.has_ammunition():
		return false
	if not solution.attack_direction.is_finite() \
			or not solution.final_aim_impact_position.is_finite() \
			or not solution.release_position.is_finite():
		return false
	if next_dive_data.dive_speed_mps <= 0.0 \
			or next_dive_data.dive_angle_degrees <= 0.0 \
			or next_dive_data.dive_angle_degrees >= 90.0:
		return false
	return true


func update(delta: float) -> void:
	var aircraft := attack_state.get_aircraft()
	if aircraft == null or not aircraft.is_alive():
		attack_state.state = DiveBombAircraftAttackState.State.DESTROYED
		attack_state.release_block_reason = \
			DiveBombReleaseBlockReason.Type.AIRCRAFT_DESTROYED
		return
	if not is_terminal() and _has_lost_movement_ownership(aircraft):
		# A lifecycle override (return, carrier loss, shutdown) took the
		# aircraft. This attack can no longer steer, so it must not keep
		# evaluating release windows or re-apply its old dive direction.
		attack_state.release_block_reason = \
			DiveBombReleaseBlockReason.Type.MOVEMENT_OWNERSHIP_LOST
		attack_state.state = DiveBombAircraftAttackState.State.FAILED
		return
	match attack_state.state:
		DiveBombAircraftAttackState.State.APPROACHING:
			_update_approach(aircraft)
		DiveBombAircraftAttackState.State.ALIGNING:
			_update_alignment(aircraft, delta)
		DiveBombAircraftAttackState.State.DIVING:
			_update_dive(aircraft, delta)
		DiveBombAircraftAttackState.State.RELEASED, \
				DiveBombAircraftAttackState.State.PULLING_OUT:
			_update_pull_out(aircraft, delta)
		_:
			pass


func get_state() -> DiveBombAircraftAttackState.State:
	return attack_state.state


func is_terminal() -> bool:
	return attack_state.is_terminal()


func is_attack_resolved() -> bool:
	return attack_state.is_attack_resolved()


## Aborts the attack. Ammunition not yet consumed stays aboard, projectiles
## already spawned keep flying, and the attack generation moves on so any
## late release outcome from the aborted attack is ignored. Movement
## ownership is returned so formation control resumes immediately.
func cancel(reason: StringName = &"cancelled") -> void:
	attack_generation += 1
	if is_terminal():
		release_movement_ownership(reason)
		return
	attack_state.release_block_reason = \
		DiveBombReleaseBlockReason.Type.CANCELLED
	attack_state.state = DiveBombAircraftAttackState.State.FAILED
	release_movement_ownership(reason)


## Idempotent: safe to call from every cleanup path, in any order, any number
## of times. Only touches the aircraft while this controller's acquire is
## still the active ownership.
func release_movement_ownership(reason: StringName = &"") -> void:
	if _movement_ownership_released:
		return
	_movement_ownership_released = true
	var aircraft := attack_state.get_aircraft()
	if aircraft != null:
		aircraft.release_movement_owner(
			AircraftMovementOwner.Type.DIVE_BOMB_ATTACK,
			reason
		)


func shutdown() -> void:
	cancel(&"shutdown")


func has_released_payload() -> bool:
	return attack_state.released


func mark_regrouped() -> void:
	release_movement_ownership(&"regroup")
	if attack_state.state in [
		DiveBombAircraftAttackState.State.FAILED,
		DiveBombAircraftAttackState.State.DESTROYED,
	]:
		return
	attack_state.state = DiveBombAircraftAttackState.State.REGROUPING


func _has_lost_movement_ownership(aircraft: AircraftUnit) -> bool:
	if _movement_ownership_released:
		return true
	if not aircraft.is_movement_owned_by(
		AircraftMovementOwner.Type.DIVE_BOMB_ATTACK
	):
		return true
	return aircraft.movement_owner_generation != _owned_movement_generation


func get_debug_snapshot() -> Dictionary:
	return {
		"aircraft_instance_id": attack_state.aircraft_instance_id,
		"aircraft_combat_id": attack_state.aircraft_combat_id,
		"aircraft_slot_id": attack_state.aircraft_slot_id,
		"state": DiveBombAircraftAttackState.State.keys()[
			int(attack_state.state)
		],
		"release_block_reason": DiveBombReleaseBlockReason.Type.keys()[
			int(attack_state.release_block_reason)
		],
		"released": attack_state.released,
		"ammunition_consumed": attack_state.ammunition_consumed,
		"degraded_release_used": attack_state.degraded_release_used,
		"release_retry_count": attack_state.release_retry_count,
		"attack_generation": attack_generation,
		"movement_owner_generation": _owned_movement_generation,
		"movement_ownership_released": _movement_ownership_released,
		"dive_elapsed_sec": attack_state.dive_elapsed_sec,
		"last_release_altitude_m": attack_state.last_release_altitude_m,
		"last_release_remaining_m": attack_state.last_release_remaining_m,
		"last_predicted_forward_error_m":
			attack_state.last_predicted_forward_error_m,
		"last_predicted_lateral_error_m":
			attack_state.last_predicted_lateral_error_m,
		"solution": attack_state.solution.to_debug_dictionary() \
			if attack_state.solution != null else {},
	}


func _update_alignment(aircraft: AircraftUnit, delta: float) -> void:
	attack_state.alignment_elapsed_sec += maxf(delta, 0.0)
	var direction := attack_state.locked_attack_direction
	aircraft.set_direct_flight_owned(
		direction,
		maxf(dive_data.dive_speed_mps, 1.0),
		AircraftMovementOwner.Type.DIVE_BOMB_ATTACK
	)
	var forward := _flat_direction(aircraft.get_forward_direction())
	var angle_error := rad_to_deg(acos(clampf(
		forward.dot(direction),
		-1.0,
		1.0
	)))
	var allowed_error := maxf(
		dive_data.quick_dive_max_heading_error_degrees \
			if attack_mode == DiveBombAttackMode.Type.QUICK_ATTACK \
			else dive_data.maximum_release_heading_error_degrees,
		0.0
	)
	if angle_error <= allowed_error:
		attack_state.state = DiveBombAircraftAttackState.State.DIVING
		return
	if attack_mode == DiveBombAttackMode.Type.QUICK_ATTACK \
			and attack_state.alignment_elapsed_sec \
				>= maxf(dive_data.quick_dive_alignment_time_sec, 0.0):
		attack_state.release_block_reason = \
			DiveBombReleaseBlockReason.Type.HEADING_NOT_ALIGNED
		_begin_pull_out(false)


func _update_approach(aircraft: AircraftUnit) -> void:
	var to_entry := attack_state.solution.dive_entry_position \
		- aircraft.global_position
	var arrival_distance := maxf(
		aircraft.aircraft_data.arrival_distance_m \
			if aircraft.aircraft_data != null else 20.0,
		1.0
	)
	if to_entry.length() <= arrival_distance:
		attack_state.state = DiveBombAircraftAttackState.State.ALIGNING
		return
	aircraft.set_direct_flight_owned(
		to_entry.normalized(),
		maxf(
			aircraft.aircraft_data.cruise_speed_mps \
				if aircraft.aircraft_data != null else dive_data.dive_speed_mps,
			1.0
		),
		AircraftMovementOwner.Type.DIVE_BOMB_ATTACK
	)


func _update_dive(aircraft: AircraftUnit, delta: float) -> void:
	attack_state.dive_elapsed_sec += maxf(delta, 0.0)
	attack_state.release_retry_cooldown_sec = maxf(
		attack_state.release_retry_cooldown_sec - maxf(delta, 0.0),
		0.0
	)
	aircraft.set_direct_flight_owned(
		attack_state.locked_dive_direction,
		maxf(dive_data.dive_speed_mps, 1.0),
		AircraftMovementOwner.Type.DIVE_BOMB_ATTACK
	)
	var reason := evaluate_release_window(
		aircraft,
		attack_state,
		dive_data,
		weapon_data
	)
	attack_state.release_block_reason = reason
	if reason == DiveBombReleaseBlockReason.Type.NONE:
		if attack_state.release_retry_cooldown_sec <= 0.0:
			_release_bomb(aircraft)
		return
	if reason in [
		DiveBombReleaseBlockReason.Type.SAFETY_ALTITUDE_REACHED,
		DiveBombReleaseBlockReason.Type.NO_AMMUNITION,
		DiveBombReleaseBlockReason.Type.WEAPON_DISABLED,
		DiveBombReleaseBlockReason.Type.IMPACT_SOLUTION_INVALID,
	]:
		_begin_pull_out(false)


func evaluate_release_window(
		aircraft: AircraftUnit,
		state_value: DiveBombAircraftAttackState,
		data: DiveBomberCombatData,
		payload: AircraftWeaponData
) -> DiveBombReleaseBlockReason.Type:
	if aircraft == null or not is_instance_valid(aircraft) \
			or not aircraft.is_alive():
		return DiveBombReleaseBlockReason.Type.AIRCRAFT_DESTROYED
	if aircraft.weapon_controller == null or payload == null:
		return DiveBombReleaseBlockReason.Type.WEAPON_DISABLED
	if not aircraft.weapon_controller.has_ammunition():
		return DiveBombReleaseBlockReason.Type.NO_AMMUNITION
	if state_value.dive_elapsed_sec \
			< maxf(data.minimum_dive_time_before_release_sec, 0.0):
		return DiveBombReleaseBlockReason.Type.TOO_EARLY
	var solution := state_value.solution
	var altitude := aircraft.global_position.y \
		- solution.final_aim_impact_position.y
	state_value.last_release_altitude_m = altitude
	if altitude < maxf(data.minimum_release_altitude_m, 0.0):
		return DiveBombReleaseBlockReason.Type.SAFETY_ALTITUDE_REACHED
	if altitude > maxf(
		data.maximum_release_altitude_m,
		data.automatic_release_altitude_m
	):
		return DiveBombReleaseBlockReason.Type.TOO_EARLY
	var forward := _flat_direction(aircraft.get_world_velocity())
	if rad_to_deg(acos(clampf(
		forward.dot(state_value.locked_attack_direction),
		-1.0,
		1.0
	))) > maxf(data.maximum_release_heading_error_degrees, 0.0):
		return DiveBombReleaseBlockReason.Type.HEADING_NOT_ALIGNED
	var to_planned_release := solution.release_position \
		- aircraft.global_position
	to_planned_release.y = 0.0
	var remaining_release_distance := to_planned_release.dot(
		state_value.locked_attack_direction
	)
	state_value.last_release_remaining_m = remaining_release_distance
	# Individual aircraft do not arrive at the mathematical release point on
	# exactly the same frame. Honor the authored per-aircraft position window;
	# the narrower impact trigger remains the minimum crossing allowance.
	var trigger_margin := maxf(
		maxf(data.release_impact_trigger_margin_m, 0.0),
		maxf(data.release_position_tolerance_m, 0.0)
	)
	if remaining_release_distance > trigger_margin:
		return DiveBombReleaseBlockReason.Type.TOO_EARLY
	var maximum_error := maxf(data.maximum_predicted_impact_error_m, 0.0)
	var predicted := DiveBombBallistics.predict_impact_from_release_state(
		aircraft.global_position,
		DiveBombBallistics.resolve_bomb_initial_velocity(
			aircraft.get_world_velocity(),
			payload
		),
		solution.final_aim_impact_position.y,
		payload,
		world_gravity_mps2
	)
	if not predicted.is_finite():
		return DiveBombReleaseBlockReason.Type.IMPACT_SOLUTION_INVALID
	var offset := predicted - solution.final_aim_impact_position
	offset.y = 0.0
	var lateral := Vector3(
		-state_value.locked_attack_direction.z,
		0.0,
		state_value.locked_attack_direction.x
	)
	var lateral_error := absf(offset.dot(lateral))
	var forward_error := offset.dot(state_value.locked_attack_direction)
	state_value.last_predicted_lateral_error_m = lateral_error
	state_value.last_predicted_forward_error_m = forward_error
	if lateral_error <= maximum_error \
			and absf(forward_error) <= maxf(maximum_error, trigger_margin):
		return DiveBombReleaseBlockReason.Type.NONE
	# A finite but imperfect trajectory is an accuracy miss, not a reason to
	# carry the bomb through the target. Keep diving while there is room for
	# the geometry to improve, then release at the authored automatic altitude.
	# This preserves payload only for genuinely invalid/non-finite ballistics.
	var fallback_release_altitude := clampf(
		data.automatic_release_altitude_m,
		data.minimum_release_altitude_m,
		data.maximum_release_altitude_m
	)
	if altitude > fallback_release_altitude \
			+ maxf(data.release_altitude_tolerance_m, 0.0):
		return DiveBombReleaseBlockReason.Type.TOO_EARLY
	state_value.degraded_release_used = true
	return DiveBombReleaseBlockReason.Type.NONE


func _release_bomb(aircraft: AircraftUnit) -> void:
	if attack_state.released:
		return
	var generation_at_request := attack_generation
	attack_state.release_attempted = true
	var ammunition_before := aircraft.weapon_controller.remaining_ammunition
	var released := aircraft.weapon_controller.release(
		attack_state.solution.final_aim_impact_position,
		attack_state.solution.target_velocity,
		attack_state.aircraft_combat_id,
		attack_state.locked_attack_direction
	)
	if generation_at_request != attack_generation:
		# The attack was cancelled while the request ran. The outcome belongs
		# to the previous generation: an already spawned projectile keeps
		# flying, but a terminated controller state is never resurrected.
		return
	attack_state.released = released
	attack_state.ammunition_consumed = released \
		and aircraft.weapon_controller.remaining_ammunition \
			< ammunition_before
	if released:
		attack_state.state = DiveBombAircraftAttackState.State.RELEASED
		attack_state.release_block_reason = \
			DiveBombReleaseBlockReason.Type.NONE
		_begin_pull_out(true)
		return
	# Transient refusal (busy weapon controller, queue pressure): retry a
	# bounded number of times inside the still-open window instead of
	# instantly wasting the pass. Ammunition was not consumed, so a later
	# retry or a skip both keep the bomb aboard.
	attack_state.release_retry_count += 1
	if attack_state.release_retry_count > maxi(
		dive_data.maximum_release_retry_count,
		0
	):
		attack_state.release_block_reason = \
			DiveBombReleaseBlockReason.Type.RELEASE_RETRY_EXHAUSTED
		_begin_pull_out(false)
		return
	attack_state.release_retry_cooldown_sec = maxf(
		dive_data.release_retry_interval_sec,
		0.0
	)


func _begin_pull_out(was_released: bool) -> void:
	attack_state.released = attack_state.released or was_released
	attack_state.state = DiveBombAircraftAttackState.State.PULLING_OUT


func _update_pull_out(aircraft: AircraftUnit, delta: float) -> void:
	attack_state.pull_out_elapsed_sec += maxf(delta, 0.0)
	var angle := deg_to_rad(clampf(
		dive_data.pull_out_climb_angle_degrees,
		1.0,
		89.0
	))
	var climb_direction := (
		attack_state.locked_attack_direction * cos(angle)
		+ Vector3.UP * sin(angle)
	).normalized()
	aircraft.set_direct_flight_owned(
		climb_direction,
		maxf(dive_data.dive_speed_mps, 1.0),
		AircraftMovementOwner.Type.DIVE_BOMB_ATTACK
	)
	var desired_y := attack_state.solution.final_aim_impact_position.y \
		+ maxf(dive_data.dive_entry_altitude_m, 1.0) * 0.7
	if aircraft.global_position.y >= desired_y \
			or attack_state.pull_out_elapsed_sec >= 8.0:
		attack_state.state = DiveBombAircraftAttackState.State.REGROUPING


func _build_locked_dive_direction(attack_direction: Vector3) -> Vector3:
	var angle := deg_to_rad(clampf(dive_data.dive_angle_degrees, 1.0, 89.0))
	return (
		_flat_direction(attack_direction) * cos(angle)
		+ Vector3.DOWN * sin(angle)
	).normalized()


func _flat_direction(value: Vector3) -> Vector3:
	var flat := value
	flat.y = 0.0
	return flat.normalized() \
		if flat.length_squared() > EPSILON else Vector3.FORWARD
