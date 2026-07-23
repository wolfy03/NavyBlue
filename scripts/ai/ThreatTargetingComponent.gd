extends Node
class_name ThreatTargetingComponent

signal target_changed(previous_target: Node3D, next_target: Node3D)

@export_category("Evaluation")
@export_range(0.1, 5.0, 0.1) var evaluation_interval_sec := 1.0
@export_range(0.0, 1.0, 0.05) var evaluation_jitter_sec := 0.25
@export_range(0.0, 2.0, 0.05) var initial_evaluation_offset_max_sec := 0.5
@export var ally_damage_share_radius_m := 2500.0
@export var fallback_target_safety_radius_m := 90.0

@export_category("Debug")
@export var debug_enabled := false
@export_range(0.1, 2.0, 0.05) var debug_update_interval_sec := 0.4

var target_evaluation_count := 0
var target_change_count := 0
var current_target_score := 0.0
var best_candidate: ShipUnit
var best_candidate_score := 0.0
var current_target_lock_sec := 0.0

var _owner_ship: ShipUnit
var _role_profile: ShipAIRoleProfile
var _candidate_provider := Callable()
var _current_target: ShipUnit
var _selector := ShipTargetSelector.new()
var _memory := ThreatMemory.new()
var _assignment_tracker := FleetTargetAssignmentTracker.new()
var _fleet_controller_ref: WeakRef
var _evaluation_elapsed_sec := 0.0
var _current_evaluation_interval_sec := 1.0
var _evaluation_requested := false
var _random := RandomNumberGenerator.new()
var _last_score_breakdowns: Dictionary = {}
var _debug_elapsed_sec := 0.0
var _debug_snapshot: Dictionary = {}


func setup(
		owner_ship: ShipUnit,
		role_profile: ShipAIRoleProfile,
		candidate_provider: Callable
) -> void:
	_owner_ship = owner_ship
	_role_profile = role_profile if role_profile != null else ShipAIRoleProfile.new()
	_candidate_provider = candidate_provider
	_random.seed = owner_ship.get_instance_id() * 1103515245 + 12345
	_evaluation_elapsed_sec = -_random.randf_range(
		0.0,
		maxf(initial_evaluation_offset_max_sec, 0.0)
	)
	_schedule_next_interval()


func set_assignment_tracker(tracker: FleetTargetAssignmentTracker) -> void:
	if tracker == null or tracker == _assignment_tracker:
		return
	_assignment_tracker.unassign(_owner_ship)
	_assignment_tracker = tracker
	if _current_target != null:
		_assignment_tracker.assign(_owner_ship, _current_target)


func set_fleet_controller(controller: Node) -> void:
	_fleet_controller_ref = weakref(controller) \
		if controller != null and is_instance_valid(controller) else null
	request_immediate_evaluation()


func set_candidate_provider(provider: Callable) -> void:
	if _candidate_provider == provider:
		return
	_candidate_provider = provider
	request_immediate_evaluation()


func set_role_profile(role_profile: ShipAIRoleProfile) -> void:
	_role_profile = role_profile if role_profile != null else ShipAIRoleProfile.new()
	request_immediate_evaluation()


func update_targeting(delta: float) -> void:
	if _owner_ship == null:
		return
	_evaluation_elapsed_sec += delta
	current_target_lock_sec += delta
	_debug_elapsed_sec += delta

	if not _is_valid_candidate(_current_target):
		if _current_target != null:
			_change_target(null)
		_evaluation_requested = true

	if _evaluation_requested or _evaluation_elapsed_sec >= _current_evaluation_interval_sec:
		_evaluate_candidates()

	if debug_enabled and _debug_elapsed_sec >= debug_update_interval_sec:
		_debug_elapsed_sec = 0.0
		_refresh_debug_snapshot()


func register_damage_source(
		attacker: Node,
		damage: float,
		damage_info: Dictionary = {}
) -> void:
	if not _is_hostile_attacker(attacker):
		return
	_memory.register_damage(attacker, damage, true, damage_info)
	request_immediate_evaluation()


func register_ally_damage_source(
		attacker: Node,
		damage: float,
		damaged_max_health: float,
		damage_info: Dictionary = {}
) -> void:
	if not _is_hostile_attacker(attacker):
		return
	_memory.register_damage(
		attacker,
		damage,
		false,
		damage_info,
		-1.0,
		damaged_max_health
	)


func request_immediate_evaluation() -> void:
	_evaluation_requested = true


func get_current_target() -> ShipUnit:
	return _current_target if is_instance_valid(_current_target) else null


func clear_target() -> void:
	_change_target(null)


func force_target(next_target: Node) -> void:
	if next_target == null:
		clear_target()
		return
	var ship := next_target as ShipUnit
	if _is_valid_candidate(ship):
		_change_target(ship)


func calculate_target_score(candidate: ShipUnit) -> float:
	var breakdown := _calculate_score_breakdown(candidate)
	return float(breakdown.get("final_score", -INF))


func get_debug_score_breakdown(candidate: ShipUnit) -> Dictionary:
	if candidate == null:
		return {}
	var candidate_id := candidate.get_instance_id()
	if _last_score_breakdowns.has(candidate_id):
		return (_last_score_breakdowns[candidate_id] as Dictionary).duplicate(true)
	return _calculate_score_breakdown(candidate)


func get_debug_snapshot() -> Dictionary:
	if debug_enabled and _debug_snapshot.is_empty():
		_refresh_debug_snapshot()
	return _debug_snapshot.duplicate(true)


func get_threat_memory() -> ThreatMemory:
	return _memory


func get_time_until_next_evaluation_sec() -> float:
	return maxf(_current_evaluation_interval_sec - _evaluation_elapsed_sec, 0.0)


func _evaluate_candidates() -> void:
	_evaluation_requested = false
	_evaluation_elapsed_sec = 0.0
	_schedule_next_interval()
	target_evaluation_count += 1
	_memory.cleanup()
	_last_score_breakdowns.clear()

	var candidates := _collect_candidates()
	best_candidate = null
	best_candidate_score = -INF
	for candidate in candidates:
		_memory.record_detection(candidate)
		var breakdown := _calculate_score_breakdown(candidate)
		_last_score_breakdowns[candidate.get_instance_id()] = breakdown
		var score := float(breakdown["final_score"])
		if score > best_candidate_score:
			best_candidate_score = score
			best_candidate = candidate

	if best_candidate == null:
		current_target_score = 0.0
		_change_target(null)
		return

	var current_breakdown: Dictionary = {}
	if _is_valid_candidate(_current_target):
		current_breakdown = _last_score_breakdowns.get(
			_current_target.get_instance_id(),
			_calculate_score_breakdown(_current_target)
		)
		current_target_score = float(current_breakdown.get("final_score", -INF))
	else:
		current_target_score = -INF

	if _should_switch_target(current_breakdown):
		_change_target(best_candidate)
		current_target_score = best_candidate_score


func _should_switch_target(current_breakdown: Dictionary) -> bool:
	if not _is_valid_candidate(_current_target):
		return true
	if best_candidate == _current_target:
		return false
	var best_breakdown: Dictionary = _last_score_breakdowns.get(
		best_candidate.get_instance_id(),
		{}
	)
	var best_is_emergency := bool(best_breakdown.get("is_emergency_threat", false))
	var current_is_emergency := bool(
		current_breakdown.get("is_emergency_threat", false)
	)
	if best_is_emergency and current_is_emergency:
		if current_target_lock_sec < _role_profile.emergency_target_lock_sec:
			return false
		if current_target_score <= 0.0:
			return best_candidate_score > current_target_score + 2.0
		return best_candidate_score \
			> current_target_score * _role_profile.emergency_switch_ratio
	if best_is_emergency:
		return best_candidate_score > current_target_score
	if _is_current_target_excessively_far():
		return true
	if current_target_lock_sec < _role_profile.minimum_target_lock_sec:
		return false
	if current_target_score <= 0.0:
		return best_candidate_score > current_target_score + 5.0
	return best_candidate_score > current_target_score * _role_profile.target_switch_ratio


func _change_target(next_target: ShipUnit) -> void:
	if is_instance_valid(_current_target) and _current_target == next_target:
		return
	var previous_target: ShipUnit = _current_target \
		if is_instance_valid(_current_target) else null
	_assignment_tracker.unassign(_owner_ship)
	_current_target = next_target
	if _current_target != null:
		_assignment_tracker.assign(_owner_ship, _current_target)
	current_target_lock_sec = 0.0
	target_change_count += 1
	target_changed.emit(previous_target, _current_target)


func _collect_candidates() -> Array[ShipUnit]:
	if not _candidate_provider.is_valid():
		return []
	var values: Variant = _candidate_provider.call()
	if not values is Array:
		return []
	var candidates := _selector.collect_valid_candidates(_owner_ship, values as Array)
	var fleet_controller := get_fleet_controller()
	if fleet_controller != null and fleet_controller.has_method(&"filter_candidates_for_member"):
		var filtered: Variant = fleet_controller.call(
			&"filter_candidates_for_member",
			_owner_ship,
			candidates,
			_current_target,
			_memory
		)
		if filtered is Array:
			return filtered as Array[ShipUnit]
	return candidates


func _calculate_score_breakdown(candidate: ShipUnit) -> Dictionary:
	if not _is_valid_candidate(candidate):
		return {"final_score": -INF}
	var context := _build_context(candidate)
	var distance_score := _score_distance(context)
	var recent_damage_score := _score_recent_damage(context)
	var combat_power_score := _score_combat_power(context)
	var strategic_value_score := _score_strategic_value(context)
	var target_class_score := _score_target_class(context)
	var attack_opportunity_score := _score_attack_opportunity(context)
	var current_target_score_value := _score_current_target(context)
	var low_health_score := _score_low_health_target(context)
	var approach_cost := _score_approach_cost(context)
	var focus_fire_penalty := _score_focus_fire_penalty(context)
	var fleet_recommendation_score := _score_fleet_recommendation(context)
	var tactical_assignment_score := _score_tactical_assignment(context)
	var final_score := distance_score \
		+ recent_damage_score \
		+ combat_power_score \
		+ strategic_value_score \
		+ target_class_score \
		+ attack_opportunity_score \
		+ current_target_score_value \
		+ low_health_score \
		+ approach_cost \
		+ focus_fire_penalty \
		+ fleet_recommendation_score \
		+ tactical_assignment_score
	return {
		"final_score": final_score,
		"distance_score": distance_score,
		"recent_damage_score": recent_damage_score,
		"combat_power_score": combat_power_score,
		"strategic_value_score": strategic_value_score,
		"target_class_score": target_class_score,
		"attack_opportunity_score": attack_opportunity_score,
		"current_target_bonus": current_target_score_value,
		"low_health_score": low_health_score,
		"approach_cost": approach_cost,
		"focus_fire_penalty": focus_fire_penalty,
		"fleet_recommendation_score": fleet_recommendation_score,
		"tactical_assignment_score": tactical_assignment_score,
		"recent_damage_to_owner": context.recent_damage_to_owner,
		"recent_damage_to_allies": context.recent_damage_to_allies,
		"distance_m": context.distance_m,
		"attackers_on_candidate": context.attackers_on_candidate,
		"is_emergency_threat": context.is_emergency_threat,
	}


func _build_context(candidate: ShipUnit) -> TargetEvaluationContext:
	var context := TargetEvaluationContext.new()
	context.owner_ship = _owner_ship
	context.candidate = candidate
	var offset := candidate.global_position - _owner_ship.global_position
	offset.y = 0.0
	context.distance_squared = offset.length_squared()
	context.distance_m = sqrt(context.distance_squared)
	context.weapon_range_m = _get_owner_weapon_range_m()
	context.preferred_distance_m = context.weapon_range_m * _role_profile.preferred_range_ratio
	context.owner_health_ratio = _get_health_ratio(_owner_ship)
	context.candidate_health_ratio = _get_health_ratio(candidate)
	context.attackers_on_candidate = _assignment_tracker.get_attacker_count(candidate)
	var memory_snapshot := _memory.get_snapshot(candidate)
	context.recent_damage_to_owner = float(memory_snapshot["damage_to_owner"])
	context.recent_damage_to_allies = float(memory_snapshot["damage_to_allies"])
	context.recent_damage_to_owner_ratio = context.recent_damage_to_owner \
		/ maxf(_owner_ship.health.max_health, 1.0)
	context.recent_damage_to_allies_ratio = float(
		memory_snapshot["damage_to_allies_ratio"]
	)
	context.candidate_combat_power = _get_combat_power(candidate)
	context.candidate_strategic_value = _get_strategic_value(candidate)
	context.is_current_target = candidate == _current_target
	context.candidate_is_aiming_at_owner = candidate.get_ai_target() == _owner_ship
	_apply_fleet_recommendation(context)
	var fleet_context := _owner_ship.get_fleet_tactical_context()
	context.tactical_assigned_target = fleet_context != null \
		and fleet_context.tactical_role == FleetMemberContext.TacticalRole.INTERCEPT \
		and fleet_context.get_assigned_target() == candidate
	var damage_threat := _score_recent_damage(context)
	var emergency_distance := _get_combined_safety_radius_m(candidate) \
		+ _role_profile.tactical_clearance_m
	context.is_emergency_threat = context.is_emergency_threat \
		or damage_threat >= _role_profile.emergency_threat_threshold \
		or context.distance_m <= emergency_distance
	return context


func _score_distance(context: TargetEvaluationContext) -> float:
	var range_m := maxf(context.weapon_range_m, 1.0)
	var distance_ratio := context.distance_m / range_m
	var preferred_ratio := maxf(_role_profile.preferred_range_ratio, 0.1)
	if distance_ratio > 1.0:
		return _role_profile.distance_weight * maxf(0.2 - (distance_ratio - 1.0), -1.0)
	var fit := 1.0 - absf(distance_ratio - preferred_ratio) / maxf(preferred_ratio, 0.25)
	var score := _role_profile.distance_weight * clampf(fit, -0.5, 1.0)
	if distance_ratio < preferred_ratio * 0.35:
		score -= _role_profile.distance_weight * 0.5
	return score


func _score_recent_damage(context: TargetEvaluationContext) -> float:
	var ratio_cap := maxf(_role_profile.maximum_damage_ratio_for_scoring, 0.01)
	var self_score := clampf(
		context.recent_damage_to_owner_ratio / ratio_cap,
		0.0,
		1.0
	) * _role_profile.maximum_recent_self_damage_score
	var ally_score := clampf(
		context.recent_damage_to_allies_ratio / ratio_cap,
		0.0,
		1.0
	) * _role_profile.maximum_recent_ally_damage_score
	return self_score + ally_score


func _score_combat_power(context: TargetEvaluationContext) -> float:
	return _role_profile.combat_power_weight \
		* clampf(context.candidate_combat_power / 100.0, 0.0, 2.0)


func _score_strategic_value(context: TargetEvaluationContext) -> float:
	return _role_profile.strategic_value_weight * context.candidate_strategic_value


func _score_target_class(context: TargetEvaluationContext) -> float:
	var class_key := _get_ship_class_key(context.candidate.ship_data)
	var preference := float(_role_profile.target_class_weights.get(class_key, 1.0))
	return (preference - 1.0) * 20.0


func _score_attack_opportunity(context: TargetEvaluationContext) -> float:
	var score := 0.0
	if context.distance_m <= context.weapon_range_m:
		score += 6.0
	if context.candidate_is_aiming_at_owner:
		score += _role_profile.aiming_at_self_bonus
	return score


func _score_current_target(context: TargetEvaluationContext) -> float:
	return _role_profile.current_target_bonus if context.is_current_target else 0.0


func _score_low_health_target(context: TargetEvaluationContext) -> float:
	return _role_profile.low_health_finish_bonus \
		* clampf(1.0 - context.candidate_health_ratio, 0.0, 1.0)


func _score_approach_cost(context: TargetEvaluationContext) -> float:
	if context.distance_m <= context.weapon_range_m:
		return 0.0
	var excess_ratio := (context.distance_m - context.weapon_range_m) \
		/ maxf(context.weapon_range_m, 1.0)
	return -_role_profile.distance_weight * 0.5 * excess_ratio


func _score_focus_fire_penalty(context: TargetEvaluationContext) -> float:
	var other_attackers := context.attackers_on_candidate
	if context.is_current_target:
		other_attackers = maxi(other_attackers - 1, 0)
	var joining_slot := other_attackers + 1
	var base_penalty := 0.0
	if joining_slot == 2:
		base_penalty = 8.0
	elif joining_slot == 3:
		base_penalty = 18.0
	elif joining_slot >= 4:
		base_penalty = 18.0 + float(joining_slot - 3) * 12.0
	var penalty := -base_penalty * (_role_profile.focus_fire_penalty_weight / 10.0)
	if context.is_emergency_threat:
		penalty *= _role_profile.emergency_focus_penalty_multiplier
	return penalty


func _score_fleet_recommendation(context: TargetEvaluationContext) -> float:
	return context.fleet_recommendation_score


func _score_tactical_assignment(context: TargetEvaluationContext) -> float:
	return _role_profile.tactical_assignment_bonus \
		if context.tactical_assigned_target else 0.0


func _get_owner_weapon_range_m() -> float:
	if _owner_ship != null and _owner_ship.combat != null:
		var weapon_range := _owner_ship.combat.get_primary_weapon_range_m()
		if weapon_range > 0.0:
			return weapon_range
	return 8000.0


func _get_health_ratio(ship: ShipUnit) -> float:
	if ship == null or ship.health == null or ship.health.max_health <= 0.0:
		return 1.0
	return clampf(ship.health.current_health / ship.health.max_health, 0.0, 1.0)


func _get_combat_power(ship: ShipUnit) -> float:
	if ship == null or ship.combat == null:
		return 0.0
	if ship.combat.has_method(&"get_estimated_damage_per_second"):
		return ship.combat.get_estimated_damage_per_second()
	return 0.0


func _get_strategic_value(ship: ShipUnit) -> float:
	if ship == null or ship.ship_data == null:
		return 1.0
	return maxf(ship.ship_data.strategic_value, 0.0)


func _get_combined_safety_radius_m(candidate: ShipUnit) -> float:
	var owner_radius := 0.0
	if _owner_ship != null and _owner_ship.ship_data != null:
		owner_radius = maxf(_owner_ship.ship_data.navigation_safety_radius_m, 0.0)
	var target_radius := fallback_target_safety_radius_m
	if candidate != null and candidate.ship_data != null:
		target_radius = maxf(
			candidate.ship_data.navigation_safety_radius_m,
			fallback_target_safety_radius_m
		)
	return owner_radius + target_radius


func _get_ship_class_key(data: ShipData) -> String:
	if data == null:
		return "unknown"
	match data.ship_class:
		ShipData.ShipClass.DESTROYER:
			return "destroyer"
		ShipData.ShipClass.CRUISER:
			return "cruiser"
		ShipData.ShipClass.BATTLESHIP:
			return "battleship"
		ShipData.ShipClass.AIRCRAFT_CARRIER:
			return "aircraft_carrier"
	return "unknown"


func _is_valid_candidate(candidate) -> bool:
	if candidate == null or _owner_ship == null or not is_instance_valid(candidate):
		return false
	var ship := candidate as ShipUnit
	if ship == null or ship == _owner_ship or ship.is_queued_for_deletion() \
		or not ship.is_inside_tree() or not ship.is_alive():
		return false
	return _owner_ship.is_hostile_to(ship)


func _is_hostile_attacker(attacker: Node) -> bool:
	var attacker_ship := attacker as ShipUnit
	return attacker_ship != null and _is_valid_candidate(attacker_ship)


func _is_current_target_excessively_far() -> bool:
	if not _is_valid_candidate(_current_target):
		return true
	var max_distance := _get_owner_weapon_range_m() * 2.5
	return _owner_ship.global_position.distance_squared_to(_current_target.global_position) \
		> max_distance * max_distance


func _schedule_next_interval() -> void:
	_current_evaluation_interval_sec = maxf(
		evaluation_interval_sec + _random.randf_range(-evaluation_jitter_sec, evaluation_jitter_sec),
		0.1
	)


func get_fleet_controller() -> Node:
	if _fleet_controller_ref == null:
		return null
	return _fleet_controller_ref.get_ref() as Node


func _apply_fleet_recommendation(context: TargetEvaluationContext) -> void:
	var fleet_controller := get_fleet_controller()
	if fleet_controller == null \
			or not fleet_controller.has_method(&"get_target_recommendation"):
		return
	var recommendation: Variant = fleet_controller.call(
		&"get_target_recommendation",
		_owner_ship,
		context.candidate
	)
	if not recommendation is Dictionary:
		return
	var data := recommendation as Dictionary
	context.fleet_recommendation_score = float(data.get("score", 0.0))
	context.fleet_is_primary_target = bool(data.get("is_primary", false))
	context.fleet_is_secondary_target = bool(data.get("is_secondary", false))
	context.fleet_is_emergency_target = bool(data.get("is_emergency", false))
	context.is_emergency_threat = context.is_emergency_threat \
		or context.fleet_is_emergency_target


func _refresh_debug_snapshot() -> void:
	_debug_snapshot = {
		"current_target": _current_target,
		"current_target_score": current_target_score,
		"best_candidate": best_candidate,
		"best_candidate_score": best_candidate_score,
		"target_lock_sec": current_target_lock_sec,
		"next_evaluation_sec": get_time_until_next_evaluation_sec(),
		"current_breakdown": get_debug_score_breakdown(_current_target),
		"target_evaluation_count": target_evaluation_count,
		"target_change_count": target_change_count,
		"threat_memory_entries": _memory.get_entry_count(),
	}


func _exit_tree() -> void:
	_assignment_tracker.unassign(_owner_ship)
