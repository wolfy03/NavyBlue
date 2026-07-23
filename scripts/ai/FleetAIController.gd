extends Node
class_name FleetAIController

signal became_empty(fleet_id: StringName)

const DEFAULT_DIFFICULTY := preload("res://resources/ai_difficulty/normal.tres")

@export var fleet_id: StringName = &"fleet"
@export var team: StringName = &"neutral"
@export var difficulty_profile: AIDifficultyProfile = DEFAULT_DIFFICULTY
@export var secondary_target_limit := 3
@export var nearby_candidate_radius_m := 5500.0
@export var ally_damage_share_radius_m := 3000.0
@export var emergency_hold_sec := 6.0
@export var emergency_defense_radius_m := 2400.0
@export var role_minimum_hold_sec := 7.0
@export var primary_target_minimum_hold_sec := 6.0
@export var primary_target_switch_ratio := 1.15
@export var primary_target_current_bonus := 8.0
@export var emergency_primary_hold_sec := 3.0
@export var emergency_primary_switch_ratio := 1.1
@export var empty_fleet_grace_sec := 10.0
@export var debug_enabled := false
@export_range(0.1, 2.0, 0.05) var debug_update_interval_sec := 0.4

var assignment_tracker := FleetTargetAssignmentTracker.new()
var fleet_center := Vector3.ZERO
var fleet_average_forward := Vector3.FORWARD
var fleet_average_velocity := Vector3.ZERO
var fleet_safe_rear_direction := Vector3.BACK
var fleet_evaluation_count := 0
var role_evaluation_count := 0
var tactical_position_update_count := 0
var target_change_count := 0
var role_change_count := 0
var debug_snapshot_update_count := 0

var _member_contexts: Dictionary = {}
var _candidate_provider := Callable()
var _incoming_attackers_provider := Callable()
var _battlefield_bounds: BattlefieldBounds
var _position_solver := TacticalPositionSolver.new()
var _primary_target_ref: WeakRef
var _secondary_target_refs: Array[WeakRef] = []
var _secondary_target_ids: Dictionary = {}
var _emergency_target_ids: Dictionary = {}
var _emergency_threats: Dictionary = {}
var _emergency_cooldowns: Dictionary = {}
var _hostile_candidate_cache: Array[ShipUnit] = []
var _fleet_update_elapsed_sec := 0.0
var _role_update_elapsed_sec := 0.0
var _tactical_update_elapsed_sec := 0.0
var _cleanup_elapsed_sec := 0.0
var _debug_elapsed_sec := 0.0
var _empty_elapsed_sec := 0.0
var _empty_signal_emitted := false
var _primary_target_lock_sec := 0.0
var _primary_target_score := 0.0
var _primary_target_is_emergency := false
var _debug_snapshot: Dictionary = {}


func setup(
		next_fleet_id: StringName,
		next_team: StringName,
		candidate_provider: Callable,
		bounds: BattlefieldBounds,
		profile: AIDifficultyProfile = null,
		incoming_attackers_provider: Callable = Callable()
) -> void:
	fleet_id = next_fleet_id
	team = next_team
	_candidate_provider = candidate_provider
	_incoming_attackers_provider = incoming_attackers_provider
	_battlefield_bounds = bounds
	difficulty_profile = profile if profile != null else DEFAULT_DIFFICULTY
	_position_solver.setup(bounds)
	var offset := fmod(float(get_instance_id() % 997) * 0.017, 0.6)
	var reaction_delay := maxf(difficulty_profile.reaction_delay_sec, 0.0)
	_fleet_update_elapsed_sec = -offset - reaction_delay
	_role_update_elapsed_sec = -offset * 1.7 - reaction_delay
	_tactical_update_elapsed_sec = -offset * 2.1 - reaction_delay
	_connect_event_bus()


func _process(delta: float) -> void:
	update_fleet(delta)


func update_fleet(delta: float) -> void:
	_primary_target_lock_sec += delta
	_debug_elapsed_sec += delta
	if is_empty():
		_empty_elapsed_sec += delta
		if _empty_elapsed_sec >= empty_fleet_grace_sec and not _empty_signal_emitted:
			_empty_signal_emitted = true
			became_empty.emit(fleet_id)
		return
	_empty_elapsed_sec = 0.0
	_empty_signal_emitted = false
	_fleet_update_elapsed_sec += delta
	_role_update_elapsed_sec += delta
	_tactical_update_elapsed_sec += delta
	_cleanup_elapsed_sec += delta

	if _cleanup_elapsed_sec >= difficulty_profile.tracker_cleanup_interval_sec:
		_cleanup_elapsed_sec = 0.0
		assignment_tracker.cleanup()
		_prune_members()
		_cleanup_emergency_threats()

	if _fleet_update_elapsed_sec >= difficulty_profile.fleet_update_interval_sec:
		_fleet_update_elapsed_sec = 0.0
		_refresh_hostile_candidate_cache()
		_update_fleet_geometry()
		_evaluate_fleet_targets()
		_detect_proximity_emergencies()
		fleet_evaluation_count += 1

	if _role_update_elapsed_sec >= difficulty_profile.role_update_interval_sec:
		_role_update_elapsed_sec = 0.0
		_assign_tactical_roles(false)
		role_evaluation_count += 1

	if _tactical_update_elapsed_sec >= difficulty_profile.tactical_position_update_interval_sec:
		_tactical_update_elapsed_sec = 0.0
		_update_tactical_positions()
		tactical_position_update_count += 1

	if debug_enabled and _debug_elapsed_sec >= debug_update_interval_sec:
		_debug_elapsed_sec = 0.0
		_refresh_debug_snapshot()


func register_member(ship: ShipUnit) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var ship_id := ship.get_instance_id()
	if _member_contexts.has(ship_id):
		return
	var context := FleetMemberContext.new().setup(ship)
	context.last_role_change_sec = _now_sec() - role_minimum_hold_sec
	_member_contexts[ship_id] = context
	_empty_elapsed_sec = 0.0
	_empty_signal_emitted = false
	set_process(true)
	ship.fleet_id = fleet_id
	ship.set_fleet_controller(self)
	if not ship.tree_exiting.is_connected(_on_member_tree_exiting.bind(ship_id)):
		ship.tree_exiting.connect(_on_member_tree_exiting.bind(ship_id), CONNECT_ONE_SHOT)
	_assign_tactical_roles(true, false)


func unregister_member(ship: ShipUnit) -> void:
	if ship == null:
		return
	_unregister_member_by_id(ship.get_instance_id())


func get_members() -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for context_value in _member_contexts.values():
		var context := context_value as FleetMemberContext
		var ship := context.get_ship()
		if ship != null and is_instance_valid(ship):
			result.append(ship)
	return result


func get_alive_members() -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for ship in get_members():
		if ship.is_alive() and not ship.is_queued_for_deletion():
			result.append(ship)
	return result


func is_empty() -> bool:
	return get_alive_members().is_empty()


func owns_member(ship: ShipUnit) -> bool:
	return ship != null and _member_contexts.has(ship.get_instance_id())


func get_member_context(ship: ShipUnit) -> FleetMemberContext:
	if ship == null:
		return null
	return _member_contexts.get(ship.get_instance_id()) as FleetMemberContext


func get_primary_target() -> ShipUnit:
	return _primary_target_ref.get_ref() as ShipUnit \
		if _primary_target_ref != null else null


func get_secondary_targets() -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for target_ref in _secondary_target_refs:
		var target := target_ref.get_ref() as ShipUnit
		if target != null and is_instance_valid(target) and target.is_alive():
			result.append(target)
	return result


func get_emergency_targets() -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	var now_sec := _now_sec()
	for threat_value in _emergency_threats.values():
		var threat := threat_value as FleetThreatContext
		if threat.is_active(now_sec):
			result.append(threat.get_target())
	return result


func get_target_recommendation(owner: ShipUnit, candidate: ShipUnit) -> Dictionary:
	var is_primary := candidate == get_primary_target()
	var candidate_id := candidate.get_instance_id() if candidate != null else 0
	var is_secondary := _secondary_target_ids.has(candidate_id)
	var is_emergency := _emergency_target_ids.has(candidate_id)
	var score := 0.0
	if is_primary:
		score += 20.0
	if is_secondary:
		score += 10.0
	if is_emergency:
		score += 40.0 * difficulty_profile.emergency_response_multiplier
	var attacker_count := assignment_tracker.get_attacker_count(candidate)
	var maximum_attackers := get_maximum_attackers_for_target(candidate, is_emergency)
	if attacker_count >= maximum_attackers \
			and assignment_tracker.get_target(owner) != candidate:
		score -= 24.0 * difficulty_profile.focus_fire_efficiency
	return {
		"score": score * difficulty_profile.fleet_recommendation_multiplier,
		"is_primary": is_primary,
		"is_secondary": is_secondary,
		"is_emergency": is_emergency,
		"attacker_count": attacker_count,
		"maximum_attackers": maximum_attackers,
	}


func filter_candidates_for_member(
		owner: ShipUnit,
		candidates: Array[ShipUnit],
		current_target: ShipUnit,
		memory: ThreatMemory
) -> Array[ShipUnit]:
	if candidates.size() <= 8:
		return candidates
	var included: Dictionary = {}
	var result: Array[ShipUnit] = []
	var preferred := [get_primary_target()]
	preferred.append_array(get_secondary_targets())
	preferred.append_array(get_emergency_targets())
	preferred.append_array(memory.get_tracked_ships())
	if current_target != null:
		preferred.append(current_target)
	for target_value in preferred:
		var target := target_value as ShipUnit
		if target != null and candidates.has(target):
			_append_unique_ship(result, included, target)
	var nearby_radius_squared := nearby_candidate_radius_m * nearby_candidate_radius_m
	for candidate in candidates:
		if owner.global_position.distance_squared_to(candidate.global_position) \
				<= nearby_radius_squared:
			_append_unique_ship(result, included, candidate)
	if result.is_empty():
		for candidate in candidates.slice(0, mini(candidates.size(), 6)):
			_append_unique_ship(result, included, candidate)
	return result


func get_maximum_attackers_for_target(target: ShipUnit, emergency := false) -> int:
	var normal_maximum := 2
	if target != null and target.ship_data != null:
		match target.ship_data.ship_class:
			ShipData.ShipClass.DESTROYER:
				normal_maximum = 2
			ShipData.ShipClass.CRUISER:
				normal_maximum = 3
			ShipData.ShipClass.BATTLESHIP:
				normal_maximum = 4
			ShipData.ShipClass.AIRCRAFT_CARRIER:
				normal_maximum = 3
	var fleet_size := get_alive_members().size()
	normal_maximum = mini(normal_maximum, maxi(fleet_size, 1))
	return mini(maxi(normal_maximum + 1, 2), 4) if emergency else normal_maximum


func register_emergency_threat(
		target: ShipUnit,
		score: float,
		reason: StringName
) -> void:
	if target == null or not is_instance_valid(target):
		return
	var now_sec := _now_sec()
	var target_id := target.get_instance_id()
	if reason != &"high_value_damage" \
			and now_sec < float(_emergency_cooldowns.get(target_id, 0.0)):
		return
	var existing := _emergency_threats.get(target_id) as FleetThreatContext
	if existing == null:
		existing = FleetThreatContext.new().setup(
			target,
			score,
			reason,
			now_sec,
			emergency_hold_sec
		)
	else:
		existing.threat_score = maxf(existing.threat_score, score)
		existing.reason = reason
		existing.expires_time_sec = now_sec + emergency_hold_sec
	_emergency_threats[target_id] = existing
	_emergency_target_ids[target_id] = true
	_request_relevant_immediate_evaluations(target)
	_assign_tactical_roles(true)


func get_debug_data() -> Dictionary:
	if _debug_snapshot.is_empty():
		_refresh_debug_snapshot()
	return _debug_snapshot.duplicate(true)


func _update_fleet_geometry() -> void:
	var members := get_alive_members()
	if members.is_empty():
		fleet_center = Vector3.ZERO
		fleet_average_forward = Vector3.FORWARD
		fleet_average_velocity = Vector3.ZERO
		return
	var weighted_position := Vector3.ZERO
	var weighted_forward := Vector3.ZERO
	var weighted_velocity := Vector3.ZERO
	var total_weight := 0.0
	for ship in members:
		var context := get_member_context(ship)
		var weight := 0.35 if context.tactical_role in [
			FleetMemberContext.TacticalRole.FLANKER,
			FleetMemberContext.TacticalRole.DISENGAGE,
		] else 1.0
		weighted_position += ship.global_position * weight
		weighted_forward += -ship.global_transform.basis.z * weight
		weighted_velocity += ship.velocity * weight
		total_weight += weight
	fleet_center = weighted_position / maxf(total_weight, 0.01)
	fleet_average_velocity = weighted_velocity / maxf(total_weight, 0.01)
	if weighted_forward.length_squared() > 0.01:
		fleet_average_forward = weighted_forward.normalized()
	elif fleet_average_velocity.length_squared() > 0.01:
		fleet_average_forward = fleet_average_velocity.normalized()
	else:
		var primary := get_primary_target()
		if primary != null:
			var to_primary := primary.global_position - fleet_center
			to_primary.y = 0.0
			fleet_average_forward = to_primary.normalized() \
				if to_primary.length_squared() > 0.01 else Vector3.FORWARD
		else:
			fleet_average_forward = Vector3.FORWARD
	_update_safe_rear_direction()


func _evaluate_fleet_targets() -> void:
	var candidates := _get_hostile_candidates()
	var scored: Array[Dictionary] = []
	var current_primary := get_primary_target()
	for candidate in candidates:
		var distance_m := fleet_center.distance_to(candidate.global_position)
		var strategic_value := candidate.ship_data.strategic_value \
			if candidate.ship_data != null else 1.0
		var combat_power := candidate.combat.get_estimated_damage_per_second()
		var distance_score := 24.0 * maxf(1.0 - distance_m / 24000.0, 0.0)
		var score := strategic_value * 28.0 \
			+ minf(combat_power / 8.0, 20.0) \
			+ distance_score
		if _is_emergency_target(candidate):
			score += 35.0
		if candidate == current_primary:
			score += primary_target_current_bonus
		score -= float(assignment_tracker.get_attacker_count(candidate)) * 4.0
		scored.append({"target": candidate, "score": score})
	scored.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var first_score := float(first["score"])
			var second_score := float(second["score"])
			if not is_equal_approx(first_score, second_score):
				return first_score > second_score
			return (first["target"] as ShipUnit).get_instance_id() \
				< (second["target"] as ShipUnit).get_instance_id()
	)
	var previous_primary := current_primary
	var selected_primary := _select_primary_with_hysteresis(scored, current_primary)
	_primary_target_ref = weakref(selected_primary) if selected_primary != null else null
	_secondary_target_refs.clear()
	_secondary_target_ids.clear()
	for entry in scored:
		var candidate := entry["target"] as ShipUnit
		if candidate == selected_primary:
			continue
		_secondary_target_refs.append(weakref(candidate))
		_secondary_target_ids[candidate.get_instance_id()] = true
		if _secondary_target_refs.size() >= secondary_target_limit:
			break
	if previous_primary != get_primary_target():
		target_change_count += 1
		_primary_target_lock_sec = 0.0
	_primary_target_is_emergency = _is_emergency_target(get_primary_target())


func _select_primary_with_hysteresis(
		scored: Array[Dictionary],
		current_primary: ShipUnit
) -> ShipUnit:
	if scored.is_empty():
		_primary_target_score = 0.0
		return null
	var best_target := scored[0]["target"] as ShipUnit
	var best_score := float(scored[0]["score"])
	var current_score := -INF
	for entry in scored:
		if entry["target"] == current_primary:
			current_score = float(entry["score"])
			break
	if not _is_valid_hostile_target(current_primary) or current_score == -INF:
		_primary_target_score = best_score
		return best_target
	if best_target == current_primary:
		_primary_target_score = current_score
		return current_primary
	if _is_primary_out_of_combat_range(current_primary):
		_primary_target_score = best_score
		return best_target
	var best_is_emergency := _is_emergency_target(best_target)
	var current_is_emergency := _is_emergency_target(current_primary)
	if best_is_emergency and not current_is_emergency:
		_primary_target_score = best_score
		return best_target
	var minimum_hold := emergency_primary_hold_sec \
		if current_is_emergency else primary_target_minimum_hold_sec
	var switch_ratio := emergency_primary_switch_ratio \
		if current_is_emergency and best_is_emergency else primary_target_switch_ratio
	if _primary_target_lock_sec < minimum_hold or best_score <= current_score * switch_ratio:
		_primary_target_score = current_score
		return current_primary
	_primary_target_score = best_score
	return best_target


func _is_valid_hostile_target(target: ShipUnit) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		return false
	var members := get_alive_members()
	return not members.is_empty() and members[0].is_hostile_to(target)


func _is_primary_out_of_combat_range(target: ShipUnit) -> bool:
	if target == null:
		return true
	var maximum_range := 0.0
	for member in get_alive_members():
		maximum_range = maxf(maximum_range, member.combat.get_max_weapon_range_m())
	return maximum_range > 0.0 \
		and fleet_center.distance_squared_to(target.global_position) > pow(maximum_range * 2.5, 2.0)


func _assign_tactical_roles(force: bool, preserve_existing_roles := true) -> void:
	var members := get_alive_members()
	if members.is_empty():
		return
	members.sort_custom(
		func(first: ShipUnit, second: ShipUnit) -> bool:
			return first.get_instance_id() < second.get_instance_id()
	)
	var now_sec := _now_sec()
	var protected_ship := _select_protected_ship()
	var interceptor_assignments := _select_emergency_interceptors(members, protected_ship)
	var desired_roles: Dictionary = {}
	var cruiser_candidates: Array[ShipUnit] = []
	var destroyer_candidates: Array[ShipUnit] = []
	for ship in members:
		var context := get_member_context(ship)
		if context == null:
			continue
		var health_ratio := _get_health_ratio(ship)
		var profile := ship.ship_data.ai_role_profile
		if not ship.player_controlled and health_ratio <= profile.disengage_health_ratio:
			desired_roles[ship.get_instance_id()] = FleetMemberContext.TacticalRole.DISENGAGE
		elif ship.ship_data.ship_class == ShipData.ShipClass.AIRCRAFT_CARRIER:
			desired_roles[ship.get_instance_id()] = FleetMemberContext.TacticalRole.SUPPORT
		elif interceptor_assignments.has(ship.get_instance_id()):
			desired_roles[ship.get_instance_id()] = FleetMemberContext.TacticalRole.INTERCEPT
		elif ship.ship_data.ship_class == ShipData.ShipClass.BATTLESHIP:
			desired_roles[ship.get_instance_id()] = FleetMemberContext.TacticalRole.LINE_COMBATANT
		elif ship.ship_data.ship_class == ShipData.ShipClass.CRUISER:
			cruiser_candidates.append(ship)
		elif ship.ship_data.ship_class == ShipData.ShipClass.DESTROYER:
			destroyer_candidates.append(ship)

	var escort := _select_best_role_candidate(
		cruiser_candidates,
		FleetMemberContext.TacticalRole.ESCORT,
		protected_ship,
		preserve_existing_roles
	) if protected_ship != null else null
	for ship in cruiser_candidates:
		desired_roles[ship.get_instance_id()] = FleetMemberContext.TacticalRole.ESCORT \
			if ship == escort else FleetMemberContext.TacticalRole.LINE_COMBATANT
	var screen := _select_best_role_candidate(
		destroyer_candidates,
		FleetMemberContext.TacticalRole.SCREEN,
		protected_ship,
		preserve_existing_roles
	) if protected_ship != null else null
	for ship in destroyer_candidates:
		desired_roles[ship.get_instance_id()] = FleetMemberContext.TacticalRole.SCREEN \
			if ship == screen else FleetMemberContext.TacticalRole.FLANKER

	var role_slots: Dictionary = {}
	for ship in members:
		var context := get_member_context(ship)
		var next_role: FleetMemberContext.TacticalRole = int(desired_roles.get(
			ship.get_instance_id(),
			context.tactical_role
		))
		var can_change := force or now_sec - context.last_role_change_sec >= role_minimum_hold_sec
		if next_role != context.tactical_role and can_change:
			if next_role == FleetMemberContext.TacticalRole.INTERCEPT:
				context.previous_tactical_role = context.tactical_role
				context.temporary_role_reason = &"emergency_intercept"
			elif context.tactical_role == FleetMemberContext.TacticalRole.INTERCEPT:
				context.temporary_role_reason = &""
			context.tactical_role = next_role
			context.last_role_change_sec = now_sec
			context.tactical_position_valid = false
			context.tactical_heading_valid = false
			role_change_count += 1
		context.set_protected_ship(
			protected_ship if context.tactical_role in [
				FleetMemberContext.TacticalRole.ESCORT,
				FleetMemberContext.TacticalRole.SCREEN,
				FleetMemberContext.TacticalRole.INTERCEPT,
			] else null
		)
		if context.tactical_role == FleetMemberContext.TacticalRole.INTERCEPT:
			context.set_assigned_target(
				interceptor_assignments.get(ship.get_instance_id()) as ShipUnit
			)
		context.formation_slot_index = int(role_slots.get(context.tactical_role, 0))
		role_slots[context.tactical_role] = context.formation_slot_index + 1
		ship.on_fleet_tactical_context_changed(context)


func _select_emergency_interceptors(
		members: Array[ShipUnit],
		protected_ship: ShipUnit
) -> Dictionary:
	var selected: Dictionary = {}
	if protected_ship == null:
		return selected
	var threats := _get_sorted_emergency_targets()
	if threats.is_empty():
		return selected
	var candidates: Array[ShipUnit] = []
	var current_screen_count := 0
	var current_escort_count := 0
	for member in members:
		var context := get_member_context(member)
		if context.tactical_role == FleetMemberContext.TacticalRole.SCREEN:
			current_screen_count += 1
		elif context.tactical_role == FleetMemberContext.TacticalRole.ESCORT:
			current_escort_count += 1
		if member.player_controlled or member.ship_data.ship_class not in [
			ShipData.ShipClass.DESTROYER,
			ShipData.ShipClass.CRUISER,
		]:
			continue
		if _get_health_ratio(member) <= member.ship_data.ai_role_profile.disengage_health_ratio:
			continue
		candidates.append(member)
	var fleet_interceptor_limit := mini(3, maxi(members.size() - 1, 1))
	for threat in threats:
		if selected.size() >= fleet_interceptor_limit or candidates.is_empty():
			break
		var required := mini(
			_get_required_interceptor_count(threat, protected_ship, members.size()),
			fleet_interceptor_limit - selected.size()
		)
		var scored: Array[Dictionary] = []
		for candidate in candidates:
			scored.append({
				"ship": candidate,
				"score": _get_interceptor_suitability(candidate, threat, protected_ship),
			})
		scored.sort_custom(
			func(first: Dictionary, second: Dictionary) -> bool:
				var first_score := float(first["score"])
				var second_score := float(second["score"])
				if not is_equal_approx(first_score, second_score):
					return first_score > second_score
				return (first["ship"] as ShipUnit).get_instance_id() \
					< (second["ship"] as ShipUnit).get_instance_id()
		)
		var selected_for_threat := 0
		var remaining_candidates := scored.size()
		for entry in scored:
			if selected_for_threat >= required:
				break
			var ship := entry["ship"] as ShipUnit
			var role := get_member_context(ship).tactical_role
			var needed_after_current := required - selected_for_threat
			var alternatives_remain := remaining_candidates - 1 >= needed_after_current
			remaining_candidates -= 1
			if alternatives_remain and (
				(role == FleetMemberContext.TacticalRole.SCREEN and current_screen_count <= 1)
				or (role == FleetMemberContext.TacticalRole.ESCORT and current_escort_count <= 1)
			):
				continue
			selected[ship.get_instance_id()] = threat
			candidates.erase(ship)
			selected_for_threat += 1
			if role == FleetMemberContext.TacticalRole.SCREEN:
				current_screen_count -= 1
			elif role == FleetMemberContext.TacticalRole.ESCORT:
				current_escort_count -= 1
	return selected


func _get_required_interceptor_count(
		threat: ShipUnit,
		protected_ship: ShipUnit,
		fleet_size: int
) -> int:
	var required := 1
	if protected_ship.ship_data.ship_class == ShipData.ShipClass.AIRCRAFT_CARRIER:
		required += 1
	var threat_context := _emergency_threats.get(threat.get_instance_id()) as FleetThreatContext
	if threat_context != null and threat_context.threat_score >= 60.0:
		required += 1
	return clampi(required, 1, mini(3, maxi(fleet_size - 1, 1)))


func _get_interceptor_suitability(
		ship: ShipUnit,
		threat: ShipUnit,
		protected_ship: ShipUnit
) -> float:
	var threat_distance := ship.global_position.distance_to(threat.global_position)
	var protected_distance := ship.global_position.distance_to(protected_ship.global_position)
	var speed_score := ship.ship_data.max_speed_mps / 50.0 * 25.0
	var health_score := _get_health_ratio(ship) * 25.0
	var distance_score := maxf(1.0 - threat_distance / 8000.0, 0.0) * 30.0 \
		+ maxf(1.0 - protected_distance / 6000.0, 0.0) * 15.0
	var context := get_member_context(ship)
	var role_cost := 0.0
	match context.tactical_role:
		FleetMemberContext.TacticalRole.INTERCEPT:
			role_cost = -18.0
		FleetMemberContext.TacticalRole.ESCORT, FleetMemberContext.TacticalRole.SCREEN:
			role_cost = 14.0
		FleetMemberContext.TacticalRole.LINE_COMBATANT:
			role_cost = 8.0
	if ship.get_ai_target() != null and ship.combat.is_target_in_range(ship):
		role_cost += 8.0
	return distance_score + speed_score + health_score - role_cost


func _select_best_role_candidate(
		candidates: Array[ShipUnit],
		role: FleetMemberContext.TacticalRole,
		protected_ship: ShipUnit,
		preserve_existing_role: bool
) -> ShipUnit:
	var best: ShipUnit
	var best_score := -INF
	for ship in candidates:
		var score := _get_role_suitability(
			ship,
			role,
			protected_ship,
			preserve_existing_role
		)
		if score > best_score or (
			is_equal_approx(score, best_score)
			and best != null
			and ship.get_instance_id() < best.get_instance_id()
		):
			best = ship
			best_score = score
	return best


func _get_role_suitability(
		ship: ShipUnit,
		role: FleetMemberContext.TacticalRole,
		protected_ship: ShipUnit,
		preserve_existing_role: bool
) -> float:
	var context := get_member_context(ship)
	var score := _get_health_ratio(ship) * 25.0
	if protected_ship != null:
		score += maxf(
			1.0 - ship.global_position.distance_to(protected_ship.global_position) / 8000.0,
			0.0
		) * 25.0
	if role == FleetMemberContext.TacticalRole.SCREEN:
		score += ship.ship_data.max_speed_mps / 50.0 * 30.0
	elif role == FleetMemberContext.TacticalRole.ESCORT \
			and ship.ship_data.ship_class == ShipData.ShipClass.CRUISER:
		score += 20.0
	if preserve_existing_role and (
		context.tactical_role == role or (
		context.tactical_role == FleetMemberContext.TacticalRole.INTERCEPT
		and context.previous_tactical_role == role
	)):
		score += 18.0
	if context.tactical_position_valid \
			and ship.global_position.distance_squared_to(context.tactical_position) < 500.0 * 500.0:
		score += 6.0
	return score


func _update_tactical_positions() -> void:
	var threat_target := _get_highest_emergency_target()
	if threat_target == null:
		threat_target = get_primary_target()
	var threat_position := threat_target.global_position \
		if threat_target != null else fleet_center + fleet_average_forward * 5000.0
	var threat_direction := threat_position - fleet_center
	threat_direction.y = 0.0
	var now_sec := _now_sec()
	for ship in get_alive_members():
		if ship.player_controlled:
			continue
		var context := get_member_context(ship)
		if now_sec < context.tactical_position_invalid_until_sec:
			continue
		var target := ship.get_ai_target() as ShipUnit
		if target == null:
			target = get_primary_target()
		var result := TacticalPositionResult.new()
		var target_changed := target != null \
			and target.get_instance_id() != context.last_tactical_target_instance_id
		var can_switch_side := target_changed \
			or now_sec - context.last_side_change_sec >= _get_minimum_side_hold_sec(ship)
		match context.tactical_role:
			FleetMemberContext.TacticalRole.LINE_COMBATANT:
				if target != null:
					var preferred_distance := ship.combat.get_primary_weapon_range_m() \
						* ship.ship_data.ai_role_profile.preferred_range_ratio
					if _get_health_ratio(ship) <= ship.ship_data.ai_role_profile.caution_health_ratio:
						preferred_distance *= ship.ship_data.ai_role_profile.damaged_preferred_range_multiplier
					result = _position_solver.calculate_line_combat_position(
						ship,
						target,
						preferred_distance,
						context.tactical_side_sign,
						850.0 + float(context.formation_slot_index) * 250.0,
						can_switch_side
					)
			FleetMemberContext.TacticalRole.ESCORT:
				var protected := context.get_protected_ship()
				if protected != null:
					result = _position_solver.calculate_escort_position(
						ship,
						protected,
						threat_position,
						context.formation_slot_index
					)
			FleetMemberContext.TacticalRole.SCREEN:
				var protected := context.get_protected_ship()
				if protected != null:
					result = _position_solver.calculate_screen_position(
						ship,
						protected,
						threat_direction,
						context.formation_slot_index
					)
			FleetMemberContext.TacticalRole.INTERCEPT:
				var protected := context.get_protected_ship()
				var assigned_threat := context.get_assigned_target()
				if not _is_emergency_target(assigned_threat):
					assigned_threat = threat_target
				if assigned_threat != null and protected != null:
					target = assigned_threat
					var profile := ship.ship_data.ai_role_profile
					var intercept_distance := ship.get_navigation_safety_radius_m() \
						+ assigned_threat.get_navigation_safety_radius_m() \
						+ profile.tactical_clearance_m \
						+ profile.intercept_buffer_m
					result = _position_solver.calculate_intercept_position(
						ship,
						protected,
						assigned_threat,
						intercept_distance,
						profile.intercept_prediction_sec
					)
			FleetMemberContext.TacticalRole.FLANKER:
				if target != null:
					result = _position_solver.calculate_flank_position(
						ship,
						target,
						context.tactical_side_sign,
						can_switch_side
					)
			FleetMemberContext.TacticalRole.SUPPORT:
				result = _position_solver.calculate_support_position(
					ship,
					fleet_center,
					fleet_safe_rear_direction,
					context.formation_slot_index
				)
			FleetMemberContext.TacticalRole.DISENGAGE:
				result = _position_solver.calculate_disengage_position(
					ship,
					fleet_center,
					threat_direction
				)
		if result.requires_side_switch and can_switch_side:
			context.tactical_side_sign = result.side_sign
			context.last_side_change_sec = now_sec
		context.set_assigned_target(target)
		if result.valid:
			result.position += _get_difficulty_position_error(ship, context, target, now_sec)
			if _battlefield_bounds != null:
				var clamped := _battlefield_bounds.clamp_to_bounds(result.position, 300.0)
				result.was_clamped = result.was_clamped \
					or result.position.distance_squared_to(clamped) > 1.0
				result.position = clamped
		context.apply_tactical_result(result, target, now_sec)
		ship.on_fleet_tactical_context_changed(context)


func report_tactical_path_failure(ship: ShipUnit) -> void:
	var context := get_member_context(ship)
	if context == null:
		return
	var now_sec := _now_sec()
	if now_sec - context.last_tactical_path_failure_sec > 8.0:
		context.tactical_path_failure_count = 0
	context.tactical_path_failure_count += 1
	context.last_tactical_path_failure_sec = now_sec
	context.tactical_position_invalid_until_sec = now_sec + 2.0
	ship.navigation.clear_navigation_target()
	if context.tactical_path_failure_count >= 2 \
			and now_sec - context.last_side_change_sec >= _get_minimum_side_hold_sec(ship):
		context.tactical_side_sign *= -1.0
		context.last_side_change_sec = now_sec
		context.tactical_path_failure_count = 0
		context.tactical_position_valid = false
		_tactical_update_elapsed_sec = difficulty_profile.tactical_position_update_interval_sec
		return
	var toward_fleet := fleet_center - ship.global_position
	toward_fleet.y = 0.0
	if toward_fleet.length_squared() > 1.0:
		context.tactical_position = _position_solver.clamp_position(
			ship.global_position + toward_fleet.normalized() * 800.0
		)
		context.tactical_heading = toward_fleet.normalized()
		context.tactical_position_valid = true
		context.tactical_heading_valid = true


func _select_protected_ship() -> ShipUnit:
	var best_ship: ShipUnit
	var best_score := -INF
	for ship in get_alive_members():
		var score := get_protected_ship_score(ship)
		if score > best_score:
			best_score = score
			best_ship = ship
	return best_ship


func get_protected_ship_score(ship: ShipUnit) -> float:
	if ship == null:
		return -INF
	var health_ratio := _get_health_ratio(ship)
	return ship.ship_data.strategic_value * 20.0 \
		+ float(_get_incoming_attacker_count(ship)) * 10.0 \
		+ _get_recent_damage_ratio(ship) * 25.0 \
		+ (1.0 - health_ratio) * 18.0 \
		+ _get_nearby_emergency_score(ship) * 0.25 \
		- float(_get_protector_count(ship)) * 4.0 \
		+ (12.0 if ship.ship_data.ship_class == ShipData.ShipClass.AIRCRAFT_CARRIER else 0.0) \
		+ (4.0 if ship.player_controlled else 0.0)


func _get_incoming_attacker_count(ship: ShipUnit) -> int:
	if ship == null or not _incoming_attackers_provider.is_valid():
		return 0
	var result: Variant = _incoming_attackers_provider.call(ship)
	return (result as Array).size() if result is Array else int(result)


func _get_recent_damage_ratio(ship: ShipUnit) -> float:
	if ship == null or ship.targeting == null:
		return 0.0
	var memory := ship.targeting.get_threat_memory()
	var total_damage := 0.0
	for attacker in memory.get_tracked_ships():
		total_damage += float(memory.get_snapshot(attacker).get("damage_to_owner", 0.0))
	return clampf(total_damage / maxf(ship.health.max_health, 1.0), 0.0, 2.0)


func _get_nearby_emergency_score(ship: ShipUnit) -> float:
	var score := 0.0
	var radius_squared := emergency_defense_radius_m * emergency_defense_radius_m
	for threat_value in _emergency_threats.values():
		var threat := threat_value as FleetThreatContext
		var target := threat.get_target()
		if target != null and target.global_position.distance_squared_to(ship.global_position) <= radius_squared:
			score += threat.threat_score
	return score


func _get_protector_count(ship: ShipUnit) -> int:
	var count := 0
	for context_value in _member_contexts.values():
		var context := context_value as FleetMemberContext
		if context.get_protected_ship() == ship and context.tactical_role in [
			FleetMemberContext.TacticalRole.ESCORT,
			FleetMemberContext.TacticalRole.SCREEN,
		]:
			count += 1
	return count


func _detect_proximity_emergencies() -> void:
	var valuable_members: Array[ShipUnit] = []
	for member in get_alive_members():
		if member.ship_data.strategic_value >= 1.2:
			valuable_members.append(member)
	var radius_squared := emergency_defense_radius_m * emergency_defense_radius_m
	for enemy in _get_hostile_candidates():
		if enemy.ship_data.ship_class != ShipData.ShipClass.DESTROYER:
			continue
		for valuable in valuable_members:
			if enemy.global_position.distance_squared_to(valuable.global_position) \
					<= radius_squared:
				register_emergency_threat(enemy, 45.0, &"capital_ship_proximity")
				break


func _on_ship_damaged(
		damaged_ship: Node,
		damage: float,
		damage_info: Dictionary
) -> void:
	var damaged := damaged_ship as ShipUnit
	if damaged == null or not owns_member(damaged):
		return
	var attacker := damage_info.get("attacker_ship") as ShipUnit
	if attacker == null or not damaged.is_hostile_to(attacker):
		return
	var damage_ratio := damage / maxf(damaged.health.max_health, 1.0)
	var share_radius_squared := ally_damage_share_radius_m * ally_damage_share_radius_m
	for member in get_alive_members():
		if member == damaged or member.player_controlled:
			continue
		var context := get_member_context(member)
		var is_relevant_role := context.tactical_role in [
			FleetMemberContext.TacticalRole.ESCORT,
			FleetMemberContext.TacticalRole.SCREEN,
			FleetMemberContext.TacticalRole.INTERCEPT,
		]
		if not is_relevant_role and member.global_position.distance_squared_to(damaged.global_position) \
				> share_radius_squared:
			continue
		member.targeting.register_ally_damage_source(
			attacker,
			damage,
			damaged.health.max_health,
			damage_info
		)
	if damage_ratio >= 0.12 or (
			damaged.ship_data.strategic_value >= 1.2 and damage_ratio >= 0.07
	):
		register_emergency_threat(
			attacker,
			damage_ratio * 100.0,
			&"high_value_damage"
		)


func _request_relevant_immediate_evaluations(target: ShipUnit) -> void:
	var radius_squared := ally_damage_share_radius_m * ally_damage_share_radius_m
	for member in get_alive_members():
		if member.player_controlled:
			continue
		var context := get_member_context(member)
		var protected := context.get_protected_ship()
		var relevant_role := context.tactical_role in [
			FleetMemberContext.TacticalRole.ESCORT,
			FleetMemberContext.TacticalRole.SCREEN,
			FleetMemberContext.TacticalRole.INTERCEPT,
		]
		var near_threat := member.global_position.distance_squared_to(target.global_position) \
			<= radius_squared
		var protects_nearby_ship := protected != null \
			and protected.global_position.distance_squared_to(target.global_position) \
				<= emergency_defense_radius_m * emergency_defense_radius_m
		if relevant_role and (near_threat or protects_nearby_ship):
			member.targeting.request_immediate_evaluation()


func _update_safe_rear_direction() -> void:
	var weighted_threat := Vector3.ZERO
	var total_weight := 0.0
	for enemy in _get_hostile_candidates():
		var direction := enemy.global_position - fleet_center
		direction.y = 0.0
		if direction.length_squared() < 1.0:
			continue
		var weight := enemy.ship_data.strategic_value \
			/ maxf(direction.length() / 5000.0, 0.5)
		weighted_threat += direction.normalized() * weight
		total_weight += weight
	var rear := -weighted_threat / maxf(total_weight, 0.01)
	if rear.length_squared() < 0.01:
		rear = -fleet_average_forward
	var toward_center := -fleet_center
	toward_center.y = 0.0
	if _battlefield_bounds != null \
			and _battlefield_bounds.get_distance_to_boundary(fleet_center) < 2500.0 \
			and toward_center.length_squared() > 1.0:
		rear = rear.normalized() * 0.65 + toward_center.normalized() * 0.35
	fleet_safe_rear_direction = rear.normalized()


func _get_hostile_candidates() -> Array[ShipUnit]:
	return _hostile_candidate_cache


func _refresh_hostile_candidate_cache() -> void:
	_hostile_candidate_cache.clear()
	if not _candidate_provider.is_valid():
		return
	var values: Variant = _candidate_provider.call()
	if not values is Array:
		return
	var members := get_alive_members()
	if members.is_empty():
		return
	var representative := members[0]
	for value in values as Array:
		var candidate := value as ShipUnit
		if candidate == null or owns_member(candidate) or not candidate.is_alive():
			continue
		if representative.is_hostile_to(candidate):
			_hostile_candidate_cache.append(candidate)


func _get_highest_emergency_target() -> ShipUnit:
	var best_target: ShipUnit
	var best_score := -INF
	var now_sec := _now_sec()
	for threat_value in _emergency_threats.values():
		var threat := threat_value as FleetThreatContext
		if threat.is_active(now_sec) and threat.threat_score > best_score:
			best_score = threat.threat_score
			best_target = threat.get_target()
	return best_target


func _get_sorted_emergency_targets() -> Array[ShipUnit]:
	var scored: Array[Dictionary] = []
	var now_sec := _now_sec()
	for threat_value in _emergency_threats.values():
		var threat := threat_value as FleetThreatContext
		var target := threat.get_target()
		if target != null and threat.is_active(now_sec):
			scored.append({
				"target": target,
				"score": threat.threat_score,
			})
	scored.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var first_score := float(first["score"])
			var second_score := float(second["score"])
			if not is_equal_approx(first_score, second_score):
				return first_score > second_score
			return (first["target"] as ShipUnit).get_instance_id() \
				< (second["target"] as ShipUnit).get_instance_id()
	)
	var result: Array[ShipUnit] = []
	for entry in scored:
		result.append(entry["target"] as ShipUnit)
	return result


func _is_emergency_target(target: ShipUnit) -> bool:
	if target == null or not _emergency_threats.has(target.get_instance_id()):
		return false
	var threat := _emergency_threats[target.get_instance_id()] as FleetThreatContext
	return threat.is_active(_now_sec())


func _cleanup_emergency_threats() -> void:
	var now_sec := _now_sec()
	for target_id in _emergency_threats.keys():
		var threat := _emergency_threats[target_id] as FleetThreatContext
		if not threat.is_active(now_sec):
			_emergency_threats.erase(target_id)
			_emergency_target_ids.erase(target_id)
			_emergency_cooldowns[target_id] = now_sec + 2.0
			_role_update_elapsed_sec = difficulty_profile.role_update_interval_sec
	for target_id in _emergency_cooldowns.keys():
		if now_sec >= float(_emergency_cooldowns[target_id]):
			_emergency_cooldowns.erase(target_id)


func _prune_members() -> void:
	for ship_id in _member_contexts.keys():
		var context := _member_contexts[ship_id] as FleetMemberContext
		var ship := context.get_ship()
		if ship == null or not is_instance_valid(ship) or not ship.is_alive():
			_unregister_member_by_id(ship_id)


func _unregister_member_by_id(ship_id: int) -> void:
	if not _member_contexts.has(ship_id):
		return
	var context := _member_contexts[ship_id] as FleetMemberContext
	var ship := context.get_ship()
	if ship != null:
		assignment_tracker.unassign(ship)
		if ship.is_inside_tree() and ship.get_fleet_controller() == self:
			ship.set_fleet_controller(null)
			ship.fleet_id = &""
	_member_contexts.erase(ship_id)


func _on_member_tree_exiting(ship_id: int) -> void:
	_unregister_member_by_id(ship_id)


func _get_health_ratio(ship: ShipUnit) -> float:
	return clampf(
		ship.health.current_health / maxf(ship.health.max_health, 1.0),
		0.0,
		1.0
	)


func _get_difficulty_position_error(
		ship: ShipUnit,
		context: FleetMemberContext,
		target: ShipUnit,
		now_sec: float
) -> Vector3:
	var error_m := difficulty_profile.tactical_position_error_m
	if error_m <= 0.0:
		return Vector3.ZERO
	var target_id := target.get_instance_id() if target != null else 0
	var error_expired := now_sec >= context.tactical_error_expire_sec
	var inputs_changed := context.tactical_error_target_instance_id != target_id \
		or context.tactical_error_role != context.tactical_role \
		or not is_equal_approx(context.tactical_error_side_sign, context.tactical_side_sign) \
		or context.tactical_error_profile_id != difficulty_profile.difficulty_id
	if error_expired or inputs_changed:
		var seed_value := hash([
			ship.get_instance_id(),
			target_id,
			int(context.tactical_role),
			int(context.tactical_side_sign),
		])
		var normalized_seed := float(abs(seed_value) % 10000) / 10000.0
		var magnitude_seed := float(abs(seed_value / 10000) % 10000) / 10000.0
		var angle := normalized_seed * TAU
		context.tactical_error_offset = Vector3(cos(angle), 0.0, sin(angle)) \
			* error_m * lerpf(0.45, 1.0, magnitude_seed)
		context.tactical_error_expire_sec = now_sec \
			+ maxf(difficulty_profile.tactical_error_hold_sec, 1.0)
		context.tactical_error_target_instance_id = target_id
		context.tactical_error_role = context.tactical_role
		context.tactical_error_side_sign = context.tactical_side_sign
		context.tactical_error_profile_id = difficulty_profile.difficulty_id
	return context.tactical_error_offset


func _get_minimum_side_hold_sec(ship: ShipUnit) -> float:
	if ship != null and ship.ship_data != null and ship.ship_data.ai_role_profile != null:
		return maxf(ship.ship_data.ai_role_profile.minimum_side_hold_sec, 1.0)
	return 10.0


func _append_unique_ship(
		result: Array[ShipUnit],
		included: Dictionary,
		ship: ShipUnit
) -> void:
	var ship_id := ship.get_instance_id()
	if included.has(ship_id):
		return
	included[ship_id] = true
	result.append(ship)


func _refresh_debug_snapshot() -> void:
	debug_snapshot_update_count += 1
	var role_counts: Dictionary = {}
	for context_value in _member_contexts.values():
		var context := context_value as FleetMemberContext
		var role_name := context.get_role_name()
		role_counts[role_name] = int(role_counts.get(role_name, 0)) + 1
	_debug_snapshot = {
		"fleet_id": fleet_id,
		"team": team,
		"member_count": get_alive_members().size(),
		"fleet_center": fleet_center,
		"fleet_average_forward": fleet_average_forward,
		"fleet_average_velocity": fleet_average_velocity,
		"fleet_safe_rear_direction": fleet_safe_rear_direction,
		"primary_target": get_primary_target(),
		"secondary_targets": get_secondary_targets(),
		"emergency_targets": get_emergency_targets(),
		"target_counts": assignment_tracker.get_debug_target_counts(),
		"role_counts": role_counts,
		"fleet_evaluation_count": fleet_evaluation_count,
		"role_evaluation_count": role_evaluation_count,
		"tactical_position_update_count": tactical_position_update_count,
		"tracker_cleanup_count": assignment_tracker.cleanup_count,
		"target_change_count": target_change_count,
		"role_change_count": role_change_count,
		"debug_snapshot_update_count": debug_snapshot_update_count,
	}


func _connect_event_bus() -> void:
	if not has_node("/root/EventBus"):
		return
	var event_bus := get_node("/root/EventBus")
	if not event_bus.ship_damaged.is_connected(_on_ship_damaged):
		event_bus.ship_damaged.connect(_on_ship_damaged)


func _exit_tree() -> void:
	assignment_tracker.clear_all()
	_hostile_candidate_cache.clear()
	_secondary_target_ids.clear()
	_emergency_target_ids.clear()
	if has_node("/root/EventBus"):
		var event_bus := get_node("/root/EventBus")
		if event_bus.ship_damaged.is_connected(_on_ship_damaged):
			event_bus.ship_damaged.disconnect(_on_ship_damaged)


func _now_sec() -> float:
	return float(Time.get_ticks_msec()) * 0.001
