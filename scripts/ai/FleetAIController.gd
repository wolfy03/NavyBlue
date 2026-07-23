extends Node
class_name FleetAIController

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
@export var debug_enabled := false

var assignment_tracker := FleetTargetAssignmentTracker.new()
var fleet_center := Vector3.ZERO
var fleet_average_forward := Vector3.FORWARD
var fleet_average_velocity := Vector3.ZERO
var fleet_safe_rear_direction := Vector3.BACK
var fleet_evaluation_count := 0
var role_evaluation_count := 0
var tactical_position_update_count := 0
var target_change_count := 0

var _member_contexts: Dictionary = {}
var _candidate_provider := Callable()
var _battlefield_bounds: BattlefieldBounds
var _position_solver := TacticalPositionSolver.new()
var _primary_target_ref: WeakRef
var _secondary_target_refs: Array[WeakRef] = []
var _emergency_threats: Dictionary = {}
var _emergency_cooldowns: Dictionary = {}
var _fleet_update_elapsed_sec := 0.0
var _role_update_elapsed_sec := 0.0
var _tactical_update_elapsed_sec := 0.0
var _cleanup_elapsed_sec := 0.0
var _debug_snapshot: Dictionary = {}


func setup(
		next_fleet_id: StringName,
		next_team: StringName,
		candidate_provider: Callable,
		bounds: BattlefieldBounds,
		profile: AIDifficultyProfile = null
) -> void:
	fleet_id = next_fleet_id
	team = next_team
	_candidate_provider = candidate_provider
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

	if debug_enabled:
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
	ship.fleet_id = fleet_id
	ship.set_fleet_controller(self)
	if not ship.tree_exiting.is_connected(_on_member_tree_exiting.bind(ship_id)):
		ship.tree_exiting.connect(_on_member_tree_exiting.bind(ship_id), CONNECT_ONE_SHOT)
	_assign_tactical_roles(true)


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
	var is_secondary := get_secondary_targets().has(candidate)
	var is_emergency := _is_emergency_target(candidate)
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
	if weighted_forward.length_squared() > 1.0:
		fleet_average_forward = weighted_forward.normalized()
	var primary := get_primary_target()
	if fleet_average_forward.length_squared() < 0.01 and primary != null:
		fleet_average_forward = (primary.global_position - fleet_center).normalized()
	_update_safe_rear_direction()


func _evaluate_fleet_targets() -> void:
	var candidates := _get_hostile_candidates()
	var scored: Array[Dictionary] = []
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
		score -= float(assignment_tracker.get_attacker_count(candidate)) * 4.0
		scored.append({"target": candidate, "score": score})
	scored.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			return float(first["score"]) > float(second["score"])
	)
	var previous_primary := get_primary_target()
	_primary_target_ref = null
	_secondary_target_refs.clear()
	if not scored.is_empty():
		var primary := scored[0]["target"] as ShipUnit
		_primary_target_ref = weakref(primary)
		for index in range(1, mini(scored.size(), secondary_target_limit + 1)):
			_secondary_target_refs.append(weakref(scored[index]["target"] as ShipUnit))
	if previous_primary != get_primary_target():
		target_change_count += 1


func _assign_tactical_roles(force: bool) -> void:
	var members := get_alive_members()
	if members.is_empty():
		return
	var now_sec := _now_sec()
	var protected_ship := _select_protected_ship()
	var cruiser_index := 0
	var destroyer_index := 0
	for ship in members:
		var context := get_member_context(ship)
		if context == null:
			continue
		var next_role := context.tactical_role
		var health_ratio := ship.health.current_health / maxf(ship.health.max_health, 1.0)
		var profile := ship.ship_data.ai_role_profile
		if not ship.player_controlled and health_ratio <= profile.disengage_health_ratio:
			next_role = FleetMemberContext.TacticalRole.DISENGAGE
		elif ship.ship_data.ship_class == ShipData.ShipClass.AIRCRAFT_CARRIER:
			next_role = FleetMemberContext.TacticalRole.SUPPORT
		elif _should_intercept_emergency(ship, protected_ship):
			next_role = FleetMemberContext.TacticalRole.INTERCEPT
		else:
			match ship.ship_data.ship_class:
				ShipData.ShipClass.BATTLESHIP:
					next_role = FleetMemberContext.TacticalRole.LINE_COMBATANT
				ShipData.ShipClass.CRUISER:
					next_role = FleetMemberContext.TacticalRole.ESCORT \
						if protected_ship != null and cruiser_index % 2 == 0 \
						else FleetMemberContext.TacticalRole.LINE_COMBATANT
					cruiser_index += 1
				ShipData.ShipClass.DESTROYER:
					next_role = FleetMemberContext.TacticalRole.SCREEN \
						if destroyer_index % 2 == 0 \
						else FleetMemberContext.TacticalRole.FLANKER
					destroyer_index += 1
		var can_change := force or now_sec - context.last_role_change_sec >= role_minimum_hold_sec
		if next_role != context.tactical_role and can_change:
			context.tactical_role = next_role
			context.last_role_change_sec = now_sec
			context.tactical_position_valid = false
		context.set_protected_ship(
			protected_ship if context.tactical_role in [
				FleetMemberContext.TacticalRole.ESCORT,
				FleetMemberContext.TacticalRole.SCREEN,
				FleetMemberContext.TacticalRole.INTERCEPT,
			] else null
		)
		context.formation_slot_index = _get_role_slot_index(context.tactical_role, ship)
		ship.on_fleet_tactical_context_changed(context)


func _update_tactical_positions() -> void:
	var threat_target := _get_highest_emergency_target()
	if threat_target == null:
		threat_target = get_primary_target()
	var threat_position := threat_target.global_position \
		if threat_target != null else fleet_center + fleet_average_forward * 5000.0
	var threat_direction := threat_position - fleet_center
	threat_direction.y = 0.0
	for ship in get_alive_members():
		if ship.player_controlled:
			continue
		var context := get_member_context(ship)
		var target := ship.get_ai_target() as ShipUnit
		if target == null:
			target = get_primary_target()
		var next_position := ship.global_position
		match context.tactical_role:
			FleetMemberContext.TacticalRole.LINE_COMBATANT:
				if target != null:
					var preferred_distance := ship.combat.get_primary_weapon_range_m() \
						* ship.ship_data.ai_role_profile.preferred_range_ratio
					if _get_health_ratio(ship) <= ship.ship_data.ai_role_profile.caution_health_ratio:
						preferred_distance *= ship.ship_data.ai_role_profile.damaged_preferred_range_multiplier
					next_position = _position_solver.calculate_line_combat_position(
						ship,
						target,
						preferred_distance,
						context.tactical_side_sign,
						850.0 + float(context.formation_slot_index) * 250.0
					)
			FleetMemberContext.TacticalRole.ESCORT:
				var protected := context.get_protected_ship()
				if protected != null:
					next_position = _position_solver.calculate_escort_position(
						ship,
						protected,
						threat_position,
						context.formation_slot_index
					)
			FleetMemberContext.TacticalRole.SCREEN:
				var protected := context.get_protected_ship()
				if protected != null:
					next_position = _position_solver.calculate_screen_position(
						ship,
						protected,
						threat_direction,
						context.formation_slot_index
					)
			FleetMemberContext.TacticalRole.INTERCEPT:
				if threat_target != null:
					next_position = threat_target.global_position
			FleetMemberContext.TacticalRole.FLANKER:
				if target != null:
					next_position = _position_solver.calculate_flank_position(
						ship,
						target,
						context.tactical_side_sign
					)
			FleetMemberContext.TacticalRole.SUPPORT:
				next_position = _position_solver.calculate_support_position(
					ship,
					fleet_center,
					fleet_safe_rear_direction,
					context.formation_slot_index
				)
			FleetMemberContext.TacticalRole.DISENGAGE:
				next_position = _position_solver.calculate_disengage_position(
					ship,
					fleet_center,
					threat_direction
				)
		next_position += _get_difficulty_position_error(ship)
		if _battlefield_bounds != null:
			next_position = _battlefield_bounds.clamp_to_bounds(next_position, 300.0)
		context.tactical_position = next_position
		context.tactical_position_valid = true
		context.last_tactical_update_sec = _now_sec()
		context.set_assigned_target(target)
		ship.on_fleet_tactical_context_changed(context)


func _select_protected_ship() -> ShipUnit:
	var best_ship: ShipUnit
	var best_score := -INF
	for ship in get_alive_members():
		var health_ratio := _get_health_ratio(ship)
		var attackers := assignment_tracker.get_attacker_count(ship)
		var score := ship.ship_data.strategic_value * 20.0 \
			+ float(attackers) * 8.0 \
			+ (1.0 - health_ratio) * 18.0
		if ship.ship_data.ship_class == ShipData.ShipClass.AIRCRAFT_CARRIER:
			score += 12.0
		if ship.player_controlled:
			score += 4.0
		if score > best_score:
			best_score = score
			best_ship = ship
	return best_ship


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


func _should_intercept_emergency(ship: ShipUnit, protected_ship: ShipUnit) -> bool:
	if protected_ship == null or get_emergency_targets().is_empty():
		return false
	return ship.ship_data.ship_class in [
		ShipData.ShipClass.DESTROYER,
		ShipData.ShipClass.CRUISER,
	]


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
	var result: Array[ShipUnit] = []
	if not _candidate_provider.is_valid():
		return result
	var values: Variant = _candidate_provider.call()
	if not values is Array:
		return result
	var members := get_alive_members()
	if members.is_empty():
		return result
	var representative := members[0]
	for value in values as Array:
		var candidate := value as ShipUnit
		if candidate == null or owns_member(candidate) or not candidate.is_alive():
			continue
		if representative.is_hostile_to(candidate):
			result.append(candidate)
	return result


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
			_emergency_cooldowns[target_id] = now_sec + 2.0
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


func _get_role_slot_index(role: FleetMemberContext.TacticalRole, ship: ShipUnit) -> int:
	var index := 0
	for context_value in _member_contexts.values():
		var context := context_value as FleetMemberContext
		if context.tactical_role == role:
			if context.get_ship() == ship:
				return index
			index += 1
	return index


func _get_health_ratio(ship: ShipUnit) -> float:
	return clampf(
		ship.health.current_health / maxf(ship.health.max_health, 1.0),
		0.0,
		1.0
	)


func _get_difficulty_position_error(ship: ShipUnit) -> Vector3:
	var error_m := difficulty_profile.tactical_position_error_m
	if error_m <= 0.0:
		return Vector3.ZERO
	var seed_value := float((ship.get_instance_id() * 31 + tactical_position_update_count * 17) % 1000)
	var angle := seed_value / 1000.0 * TAU
	return Vector3(cos(angle), 0.0, sin(angle)) * error_m


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
	}


func _connect_event_bus() -> void:
	if not has_node("/root/EventBus"):
		return
	var event_bus := get_node("/root/EventBus")
	if not event_bus.ship_damaged.is_connected(_on_ship_damaged):
		event_bus.ship_damaged.connect(_on_ship_damaged)


func _exit_tree() -> void:
	assignment_tracker.clear_all()
	if has_node("/root/EventBus"):
		var event_bus := get_node("/root/EventBus")
		if event_bus.ship_damaged.is_connected(_on_ship_damaged):
			event_bus.ship_damaged.disconnect(_on_ship_damaged)


func _now_sec() -> float:
	return float(Time.get_ticks_msec()) * 0.001
