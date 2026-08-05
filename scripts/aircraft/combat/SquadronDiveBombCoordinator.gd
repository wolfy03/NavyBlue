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
}

const REPATH_INTERVAL_SEC := 0.25

var state := State.IDLE
var released_count := 0
var failed_count := 0
var destroyed_count := 0
var pending_count := 0
var pulling_out_count := 0
var regrouped_count := 0
var failure_reason: StringName = &""

var _squadron: AircraftSquadron
var _target_request: DiveBombTargetRequest
var _resolved_target: DiveBombResolvedTarget
var _attack_mode := DiveBombAttackMode.Type.NORMAL_APPROACH
var _attack_context := DiveBombAttackContext.new()
var _controllers: Array[AircraftDiveBombController] = []
var _approach_repath_left := 0.0
var _approach_destination_serial := -1
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


func cancel() -> void:
	for controller in _controllers:
		if controller != null:
			controller.cancel()
			controller.mark_regrouped()
	_controllers.clear()
	if _squadron != null and is_instance_valid(_squadron):
		_squadron.restore_formation_flight()
	_squadron = null
	_target_request = null
	_resolved_target = null
	state = State.IDLE


func is_completed() -> bool:
	return state == State.COMPLETED


func is_failed() -> bool:
	return state == State.FAILED


func is_active() -> bool:
	return state not in [State.IDLE, State.COMPLETED, State.FAILED]


func get_resolved_target() -> DiveBombResolvedTarget:
	return _resolved_target


func get_final_aim_impact_position() -> Vector3:
	return _final_aim_impact_position


func get_aircraft_controllers() -> Array[AircraftDiveBombController]:
	return _controllers.duplicate()


func get_debug_snapshot() -> Dictionary:
	var aircraft_snapshots: Array[Dictionary] = []
	for controller in _controllers:
		aircraft_snapshots.append(controller.get_debug_snapshot())
	var result := {
		"state": State.keys()[int(state)],
		"attack_mode": DiveBombAttackMode.Type.keys()[int(_attack_mode)],
		"final_aim_impact_position": _final_aim_impact_position,
		"tracking_aim_position": _tracking_aim_position,
		"tracking_error_offset": _attack_context.pass_dispersion_offset,
		"target_resolve_count": _attack_context.target_resolve_count,
		"target_reacquire_count": _attack_context.target_reacquire_count,
		"solution_revision": _attack_context.solution_revision,
		"released_count": released_count,
		"failed_count": failed_count,
		"destroyed_count": destroyed_count,
		"pending_count": pending_count,
		"pulling_out_count": pulling_out_count,
		"regrouped_count": regrouped_count,
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
	if _approach_destination_serial < 0 or _approach_repath_left <= 0.0:
		var destination := _calculate_shared_approach_destination()
		_approach_destination_serial = _squadron.set_mission_destination(
			destination,
			true,
			&"dive_bomb_approach"
		)
		_approach_repath_left = REPATH_INTERVAL_SEC
	if _squadron.has_reached_mission_destination(
		_approach_destination_serial
	):
		state = State.ATTACK_SPLIT


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
			_attack_mode
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
	for controller in _controllers:
		controller.mark_regrouped()
	_squadron.restore_formation_flight()
	_regroup_destination_serial = _squadron.set_mission_destination(
		_regroup_position,
		true,
		&"dive_bomb_regroup"
	)
	_regroup_elapsed_sec = 0.0
	state = State.REGROUPING


func _update_regroup(delta: float) -> void:
	_regroup_elapsed_sec += maxf(delta, 0.0)
	var dive_data := _squadron.get_dive_bomber_combat_data()
	var alive := _squadron.get_alive_aircraft()
	var arrived := 0
	var arrival_distance := maxf(
		_squadron.squadron_data.aircraft_data.arrival_distance_m,
		1.0
	)
	for aircraft in alive:
		if aircraft.global_position.distance_to(_regroup_position) \
				<= arrival_distance * 2.0:
			arrived += 1
	var ratio := float(arrived) / float(alive.size()) \
		if not alive.is_empty() else 1.0
	if ratio >= clampf(dive_data.regroup_completion_ratio, 0.0, 1.0) \
			or _regroup_elapsed_sec >= maxf(dive_data.regroup_timeout_sec, 0.0) \
			or _squadron.has_reached_mission_destination(
				_regroup_destination_serial
			):
		regrouped_count = alive.size()
		state = State.COMPLETED if released_count > 0 else State.FAILED


func _finish_without_regroup() -> void:
	for controller in _controllers:
		controller.mark_regrouped()
	_squadron.restore_formation_flight()
	state = State.COMPLETED if released_count > 0 else State.FAILED


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
