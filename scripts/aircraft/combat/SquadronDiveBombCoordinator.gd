extends RefCounted
class_name SquadronDiveBombCoordinator
## Shared dive-bomb execution for AI missions and player commands.

enum State {
	IDLE,
	APPROACHING,
	ATTACK_SPLIT,
	ALIGNING,
	DIVING,
	PULLING_OUT,
	REGROUPING,
	COMPLETED,
	FAILED,
	CANCELLED,
}

## Why REGROUPING ended. Priority when several are true in the same frame:
## NO_SURVIVORS > RATIO_REACHED > DESTINATION_REACHED > TIMEOUT.
enum RegroupCompletionReason {
	NONE,
	RATIO_REACHED,
	DESTINATION_REACHED,
	TIMEOUT,
	NO_SURVIVORS,
	REGROUP_DISABLED,
	CANCELLED,
}

var state := State.IDLE
var released_count := 0
var failed_count := 0
var destroyed_count := 0
var pending_count := 0
var pulling_out_count := 0
## ACTUAL aircraft counted inside the regroup tolerances when regrouping
## ended - never inflated to the survivor count.
var regrouped_count := 0
var regroup_alive_count := 0
var regroup_arrived_count := 0
var regroup_completion_ratio_actual := 0.0
var regroup_completion_reason := RegroupCompletionReason.NONE
var failure_reason: StringName = &""
var movement_ownership_released_count := 0
var approach_repath_count := 0

var _squadron: AircraftSquadron
var _target_request: DiveBombTargetRequest
var _resolved_target: DiveBombResolvedTarget
var _attack_mode := DiveBombAttackMode.Type.NORMAL_APPROACH
var _attack_context := DiveBombAttackContext.new()
var _controllers: Array[AircraftDiveBombController] = []
var _approach_repath_left := 0.0
var _approach_destination_serial := -1
## The destination actually assigned to movement (post combat-radius clamp).
var _approach_position := Vector3.ZERO
## The planner's unclamped request, kept for clamp-offset diagnostics.
var _approach_requested_position := Vector3.ZERO
var _regroup_destination_serial := -1
var _regroup_elapsed_sec := 0.0
var _regroup_position := Vector3.ZERO
var _final_aim_impact_position := Vector3.ZERO
var _tracking_aim_position := Vector3.ZERO


func setup(
		squadron: AircraftSquadron,
		target_request: DiveBombTargetRequest,
		attack_mode: int,
		pass_index: int
) -> bool:
	cancel()
	if squadron == null or not is_instance_valid(squadron) \
			or target_request == null \
			or squadron.get_aircraft_role() \
				!= AircraftData.AircraftRole.DIVE_BOMBER \
			or squadron.get_dive_bomber_combat_data() == null \
			or squadron.get_aircraft_weapon_data() == null:
		state = State.FAILED
		failure_reason = &"invalid_configuration"
		return false
	_squadron = squadron
	_target_request = target_request
	_attack_mode = attack_mode
	_attack_context = DiveBombAttackContext.new()
	_attack_context.squadron_combat_id = CombatIdentity.for_squadron(squadron)
	_attack_context.attack_pass_index = maxi(pass_index, 1)
	_resolve_target()
	if _resolved_target == null or not _resolved_target.is_valid():
		state = State.FAILED
		failure_reason = &"target_resolution_failed"
		return false
	state = State.APPROACHING \
		if attack_mode == DiveBombAttackMode.Type.NORMAL_APPROACH \
		else State.ATTACK_SPLIT
	failure_reason = &""
	return true


func update(delta: float) -> void:
	if _squadron == null or not is_instance_valid(_squadron):
		if state not in [State.IDLE, State.COMPLETED, State.FAILED,
				State.CANCELLED]:
			# The squadron object is gone but individual aircraft may
			# outlive it; never leave them owned by orphaned controllers.
			_release_all_controller_ownership(&"squadron_unavailable")
			state = State.FAILED
			failure_reason = &"squadron_unavailable"
		return
	match state:
		State.APPROACHING:
			_update_approach(delta)
		State.ATTACK_SPLIT:
			_begin_individual_attack()
		State.ALIGNING, State.DIVING, State.PULLING_OUT:
			_update_aircraft(delta)
		State.REGROUPING:
			_update_regroup(delta)
		_:
			pass


## Cleans up from ANY state (aligning, diving, releasing, pulling out,
## regrouping, failed): every controller is cancelled and its movement
## ownership returned, exactly once, before formation control resumes.
## Ammunition not yet spent stays aboard; spawned projectiles keep flying.
func cancel(reason: StringName = &"cancelled") -> void:
	var was_active := is_active()
	_release_all_controller_ownership(reason)
	_controllers.clear()
	if _squadron != null and is_instance_valid(_squadron):
		_squadron.restore_formation_flight()
	_squadron = null
	_target_request = null
	_resolved_target = null
	if was_active:
		if state == State.REGROUPING:
			regroup_completion_reason = RegroupCompletionReason.CANCELLED
		state = State.CANCELLED
		failure_reason = reason
	else:
		state = State.IDLE


func _release_all_controller_ownership(reason: StringName) -> void:
	for controller in _controllers:
		if controller == null:
			continue
		controller.cancel(reason)
		controller.release_movement_ownership(reason)
		movement_ownership_released_count += 1


func is_completed() -> bool:
	return state == State.COMPLETED


func is_failed() -> bool:
	return state in [State.FAILED, State.CANCELLED]


func is_active() -> bool:
	return state not in [
		State.IDLE,
		State.COMPLETED,
		State.FAILED,
		State.CANCELLED,
	]


func get_resolved_target() -> DiveBombResolvedTarget:
	return _resolved_target


func get_final_aim_impact_position() -> Vector3:
	return _final_aim_impact_position


func get_aircraft_controllers() -> Array[AircraftDiveBombController]:
	return _controllers.duplicate()


func get_debug_snapshot() -> Dictionary:
	var aircraft_snapshots: Array[Dictionary] = []
	var aligning_count := 0
	var diving_count := 0
	var alignment_error_sum := 0.0
	var maximum_alignment_error := 0.0
	for controller in _controllers:
		aircraft_snapshots.append(controller.get_debug_snapshot())
		if controller.attack_state.state \
				== DiveBombAircraftAttackState.State.ALIGNING:
			aligning_count += 1
			var error := absf(
				controller.attack_state.current_heading_error_degrees
			)
			alignment_error_sum += error
			maximum_alignment_error = maxf(maximum_alignment_error, error)
		elif controller.attack_state.state \
				== DiveBombAircraftAttackState.State.DIVING:
			diving_count += 1
	var result := {
		"state": State.keys()[int(state)],
		"attack_mode": DiveBombAttackMode.Type.keys()[int(_attack_mode)],
		"final_aim_impact_position": _final_aim_impact_position,
		"tracking_aim_position": _tracking_aim_position,
		"tracking_error_offset": _attack_context.pass_dispersion_offset,
		"target_resolve_count": _attack_context.target_resolve_count,
		"target_reacquire_count": _attack_context.target_reacquire_count,
		"solution_revision": _attack_context.solution_revision,
		"approach_destination_serial": _approach_destination_serial,
		"approach_position": _approach_position,
		"approach_requested_position": _approach_requested_position,
		"approach_assigned_position": _approach_position,
		"approach_clamp_offset_m": _flat_distance(
			_approach_requested_position,
			_approach_position
		),
		"approach_repath_count": approach_repath_count,
		"approach_distance_remaining_m": _flat_distance(
			_squadron.formation_center,
			_approach_position
		) if _squadron != null and is_instance_valid(_squadron) else 0.0,
		"approach_destination_reached": (
			_squadron.has_reached_mission_destination(
				_approach_destination_serial
			) if _squadron != null and is_instance_valid(_squadron) \
			and _approach_destination_serial >= 0 else false
		),
		"released_count": released_count,
		"failed_count": failed_count,
		"destroyed_count": destroyed_count,
		"pending_count": pending_count,
		"pulling_out_count": pulling_out_count,
		"regrouped_count": regrouped_count,
		"regroup_alive_count": regroup_alive_count,
		"regroup_arrived_count": regroup_arrived_count,
		"regroup_completion_ratio_actual": regroup_completion_ratio_actual,
		"regroup_completion_reason": RegroupCompletionReason.keys()[
			int(regroup_completion_reason)
		],
		"regroup_elapsed_sec": _regroup_elapsed_sec,
		"movement_ownership_released_count":
			movement_ownership_released_count,
		"controller_count": _controllers.size(),
		"aligning_count": aligning_count,
		"diving_count": diving_count,
		"average_alignment_heading_error_deg": (
			alignment_error_sum / float(aligning_count) \
				if aligning_count > 0 else 0.0
		),
		"maximum_alignment_heading_error_deg": maximum_alignment_error,
		"failure_reason": failure_reason,
		"aircraft": aircraft_snapshots,
	}
	if _resolved_target != null:
		result.merge(_resolved_target.get_debug_snapshot(), true)
	return result


func _resolve_target() -> void:
	_attack_context.target_resolve_count += 1
	_resolved_target = DiveBombTargetResolver.resolve(
		_target_request,
		_squadron.get_dive_bomb_candidate_ships()
	)
	if _resolved_target != null and _resolved_target.is_valid():
		DiveBombAttackPlanner.ensure_pass_dispersion(
			_attack_context,
			_resolved_target,
			_squadron.get_dive_bomber_combat_data()
		)
		_tracking_aim_position = DiveBombAttackPlanner \
			.resolve_tracking_aim_position(
				_resolved_target,
				_attack_context
			)


func _update_approach(delta: float) -> void:
	if _resolved_target.is_ship_target_lost():
		_attack_context.target_reacquire_count += 1
		_resolve_target()
		if _resolved_target == null or not _resolved_target.is_valid():
			state = State.FAILED
			failure_reason = &"target_lost_during_approach"
			return
	_approach_repath_left = maxf(
		_approach_repath_left - maxf(delta, 0.0),
		0.0
	)
	var dive_data := _squadron.get_dive_bomber_combat_data()
	if _approach_destination_serial < 0 or _approach_repath_left <= 0.0:
		var destination := _calculate_shared_approach_destination()
		_approach_requested_position = destination
		# A moving target drags the computed approach point continuously;
		# only a change beyond the authored threshold issues a NEW movement
		# command (new serial). Sub-threshold drift keeps the current
		# command so arrival tracking is never reset by noise.
		var previous_serial := _approach_destination_serial
		if previous_serial < 0:
			_approach_destination_serial = _squadron.set_mission_destination(
				destination,
				true,
				&"dive_bomb_approach"
			)
		else:
			_approach_destination_serial = \
				_squadron.update_mission_destination_if_changed(
					destination,
					dive_data.approach_repath_threshold_m,
					&"dive_bomb_approach"
				)
		if _approach_destination_serial != previous_serial:
			approach_repath_count += 1
		# set_mission_destination owns combat-radius clamping. Retain the
		# authoritative destination actually assigned to movement, not the
		# unclamped planner request.
		_approach_position = _squadron.destination
		_approach_repath_left = maxf(
			dive_data.approach_repath_interval_sec,
			0.0
		)
	if _has_reached_approach_position():
		state = State.ATTACK_SPLIT


func _has_reached_approach_position() -> bool:
	if _approach_destination_serial < 0:
		return false
	return _squadron.has_reached_mission_destination(
		_approach_destination_serial
	) or _squadron.movement_controller.has_formation_arrived(
		_approach_position
	)


func _calculate_shared_approach_destination() -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for aircraft in _eligible_aircraft():
		var solution := DiveBombAttackPlanner \
			.build_aircraft_navigation_solution(
				_squadron,
				aircraft,
				_resolved_target,
				_squadron.get_dive_bomber_combat_data(),
				_squadron.get_aircraft_weapon_data(),
				true,
				_attack_context
			)
		if solution == null or not solution.valid:
			continue
		total += solution.approach_position
		count += 1
	if count > 0:
		# The formation tracks the same deterministic error point that will be
		# locked for this pass. It does not track the exact ship and then jump to
		# an inaccurate point only when the individual dive begins.
		return total / float(count) + _attack_context.pass_dispersion_offset
	return _tracking_aim_position \
		- _squadron.get_formation_forward() * 900.0


func _begin_individual_attack() -> void:
	_controllers.clear()
	# Final pre-lock refresh. Once individual controllers start, their target,
	# heading and release geometry never change.
	_resolve_target()
	if _resolved_target == null or not _resolved_target.is_valid():
		state = State.FAILED
		failure_reason = &"final_target_resolution_failed"
		return
	var aircraft_list := _eligible_aircraft()
	if aircraft_list.is_empty():
		state = State.FAILED
		failure_reason = &"no_eligible_aircraft"
		return
	var exact_impact_sum := Vector3.ZERO
	var exact_impact_count := 0
	for aircraft in aircraft_list:
		var preview_solution := DiveBombAttackPlanner \
			.build_aircraft_navigation_solution(
				_squadron,
				aircraft,
				_resolved_target,
				_squadron.get_dive_bomber_combat_data(),
				_squadron.get_aircraft_weapon_data(),
				true,
				_attack_context
			)
		if preview_solution == null or not preview_solution.valid:
			continue
		exact_impact_sum += preview_solution.exact_intended_impact_position
		exact_impact_count += 1
	if exact_impact_count == 0:
		state = State.FAILED
		failure_reason = &"no_lock_solution"
		return
	var common_exact_impact := exact_impact_sum / float(exact_impact_count)
	_final_aim_impact_position = common_exact_impact \
		+ _attack_context.pass_dispersion_offset
	_final_aim_impact_position.y = common_exact_impact.y
	for aircraft in aircraft_list:
		var solution := (
			DiveBombAttackPlanner.build_fixed_impact_navigation_solution(
				_squadron,
				aircraft,
				_final_aim_impact_position,
				_resolved_target.get_target_velocity(),
				_squadron.get_dive_bomber_combat_data(),
				_squadron.get_aircraft_weapon_data(),
				_attack_context
			)
			if _attack_mode == DiveBombAttackMode.Type.NORMAL_APPROACH
			else DiveBombAttackPlanner.build_fixed_impact_solution(
				aircraft,
				_final_aim_impact_position,
				_resolved_target.get_target_velocity(),
				_squadron.get_dive_bomber_combat_data(),
				_squadron.get_aircraft_weapon_data(),
				_attack_context
			)
		)
		if solution == null or not solution.valid:
			failed_count += 1
			continue
		var controller := AircraftDiveBombController.new()
		if controller.setup(
			aircraft,
			_squadron.get_aircraft_weapon_data(),
			_squadron.get_dive_bomber_combat_data(),
			solution,
			_attack_mode,
			_resolved_target,
			_attack_context
		):
			_controllers.append(controller)
		else:
			failed_count += 1
	if _controllers.is_empty():
		state = State.FAILED
		failure_reason = &"no_aircraft_solution"
		return
	state = State.ALIGNING


func _update_aircraft(delta: float) -> void:
	for controller in _controllers:
		controller.update(delta)
	_update_counts()
	if pending_count > 0:
		state = State.ALIGNING \
			if _has_aircraft_state(
				DiveBombAircraftAttackState.State.APPROACHING
			) or _has_aircraft_state(
				DiveBombAircraftAttackState.State.ALIGNING
			) else State.DIVING
		return
	if pulling_out_count > 0:
		state = State.PULLING_OUT
		return
	_begin_regroup()


func _begin_regroup() -> void:
	var dive_data := _squadron.get_dive_bomber_combat_data()
	if not dive_data.regroup_after_attack:
		_finish_without_regroup()
		return
	var direction := _controllers[0].attack_state.locked_attack_direction \
		if not _controllers.is_empty() else _squadron.get_formation_forward()
	_regroup_position = _final_aim_impact_position \
		+ direction * maxf(dive_data.regroup_distance_m, 0.0)
	var carrier := _squadron.get_owner_carrier()
	var aircraft_data := _squadron.squadron_data.aircraft_data
	_regroup_position.y = (
		carrier.global_position.y if carrier != null else 0.0
	) + aircraft_data.operating_altitude_m
	# Ownership policy: EVERY controller returns its aircraft to formation
	# control at the moment regroup begins, so the rally flight is flown by
	# one system for the whole squadron. No aircraft is ever mixed between a
	# live dive controller and formation steering during the regroup.
	for controller in _controllers:
		controller.mark_regrouped()
		movement_ownership_released_count += 1
	_squadron.restore_formation_flight()
	_regroup_destination_serial = _squadron.set_mission_destination(
		_regroup_position,
		true,
		&"dive_bomb_regroup"
	)
	_regroup_elapsed_sec = 0.0
	regroup_completion_reason = RegroupCompletionReason.NONE
	state = State.REGROUPING


func _update_regroup(delta: float) -> void:
	_regroup_elapsed_sec += maxf(delta, 0.0)
	var dive_data := _squadron.get_dive_bomber_combat_data()
	var alive := _squadron.get_alive_aircraft()
	var arrived := 0
	for aircraft in alive:
		if _has_aircraft_regrouped(aircraft, dive_data):
			arrived += 1
	var ratio := float(arrived) / float(alive.size()) \
		if not alive.is_empty() else 0.0
	regroup_alive_count = alive.size()
	regroup_arrived_count = arrived
	regroup_completion_ratio_actual = ratio
	# Completion causes are judged individually and recorded by priority, so
	# the stats always say WHY the regroup ended and how many actually made
	# it - a timeout can no longer masquerade as a full rally.
	var next_reason := RegroupCompletionReason.NONE
	if alive.is_empty():
		next_reason = RegroupCompletionReason.NO_SURVIVORS
	elif ratio >= clampf(dive_data.regroup_completion_ratio, 0.0, 1.0):
		next_reason = RegroupCompletionReason.RATIO_REACHED
	elif _squadron.has_reached_mission_destination(
		_regroup_destination_serial
	):
		next_reason = RegroupCompletionReason.DESTINATION_REACHED
	elif _regroup_elapsed_sec >= maxf(dive_data.regroup_timeout_sec, 0.0):
		next_reason = RegroupCompletionReason.TIMEOUT
	if next_reason == RegroupCompletionReason.NONE:
		return
	regroup_completion_reason = next_reason
	regrouped_count = arrived
	# The attack verdict comes from released bombs alone; a regroup timeout
	# is a normal ending, not a mission failure.
	state = State.COMPLETED if released_count > 0 else State.FAILED


## Split arrival test: horizontal ground-track distance and altitude error
## are judged separately. A bomber recovering from its dive can be exactly
## over the rally point long before it has climbed back to cruise altitude.
func _has_aircraft_regrouped(
		aircraft: AircraftUnit,
		dive_data: DiveBomberCombatData
) -> bool:
	var horizontal_distance := Vector2(
		aircraft.global_position.x - _regroup_position.x,
		aircraft.global_position.z - _regroup_position.z
	).length()
	if horizontal_distance > maxf(dive_data.regroup_horizontal_tolerance_m, 1.0):
		return false
	var altitude_error := absf(
		aircraft.global_position.y - _regroup_position.y
	)
	return altitude_error <= maxf(dive_data.regroup_altitude_tolerance_m, 1.0)


func _finish_without_regroup() -> void:
	for controller in _controllers:
		controller.mark_regrouped()
		movement_ownership_released_count += 1
	_squadron.restore_formation_flight()
	regroup_completion_reason = RegroupCompletionReason.REGROUP_DISABLED
	state = State.COMPLETED if released_count > 0 else State.FAILED


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _update_counts() -> void:
	released_count = 0
	failed_count = 0
	destroyed_count = 0
	pending_count = 0
	pulling_out_count = 0
	for controller in _controllers:
		var attack_state := controller.attack_state
		if attack_state.released:
			released_count += 1
		match attack_state.state:
			DiveBombAircraftAttackState.State.FAILED:
				failed_count += 1
			DiveBombAircraftAttackState.State.DESTROYED:
				destroyed_count += 1
			DiveBombAircraftAttackState.State.PULLING_OUT, \
					DiveBombAircraftAttackState.State.RELEASED:
				pulling_out_count += 1
			DiveBombAircraftAttackState.State.REGROUPING:
				pass
			_:
				pending_count += 1


func _has_aircraft_state(aircraft_state: int) -> bool:
	for controller in _controllers:
		if controller.attack_state.state == aircraft_state:
			return true
	return false


func _eligible_aircraft() -> Array[AircraftUnit]:
	var result: Array[AircraftUnit] = []
	for aircraft in _squadron.get_alive_aircraft():
		if aircraft.weapon_controller != null \
				and aircraft.weapon_controller.weapon_data != null \
				and aircraft.weapon_controller.weapon_data.weapon_type \
					== AircraftWeaponData.WeaponType.BOMB \
				and aircraft.weapon_controller.has_ammunition():
			result.append(aircraft)
	result.sort_custom(
		func(left: AircraftUnit, right: AircraftUnit) -> bool:
			return left.aircraft_slot_id < right.aircraft_slot_id
	)
	return result
