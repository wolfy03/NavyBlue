extends RefCounted
class_name EmergencyInterceptorPolicy


func assign(
		members: Array[FleetMemberContext],
		threats: Array[FleetThreatContext],
		protected_ship: ShipUnit
) -> Array[EmergencyInterceptorAssignment]:
	var assignments: Array[EmergencyInterceptorAssignment] = []
	if protected_ship == null or threats.is_empty():
		return assignments
	var candidates: Array[FleetMemberContext] = []
	var current_screen_count := 0
	var current_escort_count := 0
	for context in members:
		var member := context.get_ship() if context != null else null
		if member == null or not is_instance_valid(member):
			continue
		if context.tactical_role == FleetMemberContext.TacticalRole.SCREEN:
			current_screen_count += 1
		elif context.tactical_role == FleetMemberContext.TacticalRole.ESCORT:
			current_escort_count += 1
		if member.player_controlled or member.ship_data == null \
				or member.ship_data.ship_class not in [
					ShipData.ShipClass.DESTROYER,
					ShipData.ShipClass.CRUISER,
				]:
			continue
		if _get_health_ratio(member) \
				<= member.ship_data.ai_role_profile.disengage_health_ratio:
			continue
		candidates.append(context)
	var fleet_interceptor_limit := mini(3, maxi(members.size() - 1, 1))
	var selected_count := 0
	for threat_context in threats:
		var threat := threat_context.get_target() \
			if threat_context != null else null
		if threat == null or selected_count >= fleet_interceptor_limit \
				or candidates.is_empty():
			break
		var required := mini(
			_get_required_interceptor_count(
				threat_context,
				protected_ship,
				members.size()
			),
			fleet_interceptor_limit - selected_count
		)
		candidates.sort_custom(
			func(first: FleetMemberContext, second: FleetMemberContext) -> bool:
				var first_ship := first.get_ship()
				var second_ship := second.get_ship()
				var first_score := evaluate_suitability(
					first,
					threat,
					protected_ship
				)
				var second_score := evaluate_suitability(
					second,
					threat,
					protected_ship
				)
				if not is_equal_approx(first_score, second_score):
					return first_score > second_score
				return first_ship.get_instance_id() \
					< second_ship.get_instance_id()
		)
		var assignment := EmergencyInterceptorAssignment.new()
		assignment.threat = threat
		assignment.reason = &"emergency_intercept"
		var remaining_candidates := candidates.size()
		for context_value in candidates.duplicate():
			var context := context_value as FleetMemberContext
			if assignment.interceptors.size() >= required:
				break
			var role: FleetMemberContext.TacticalRole = \
				context.tactical_role
			var needed_after_current := required \
				- assignment.interceptors.size()
			var alternatives_remain := remaining_candidates - 1 \
				>= needed_after_current
			remaining_candidates -= 1
			if alternatives_remain and (
				(role == FleetMemberContext.TacticalRole.SCREEN
					and current_screen_count <= 1)
				or (role == FleetMemberContext.TacticalRole.ESCORT
					and current_escort_count <= 1)
			):
				continue
			var ship: ShipUnit = context.get_ship()
			assignment.interceptors.append(ship)
			candidates.erase(context)
			selected_count += 1
			if role == FleetMemberContext.TacticalRole.SCREEN:
				current_screen_count -= 1
			elif role == FleetMemberContext.TacticalRole.ESCORT:
				current_escort_count -= 1
		if not assignment.interceptors.is_empty():
			assignments.append(assignment)
	return assignments


func _get_required_interceptor_count(
		threat: FleetThreatContext,
		protected_ship: ShipUnit,
		fleet_size: int
) -> int:
	var required := 1
	if protected_ship.ship_data.ship_class \
			== ShipData.ShipClass.AIRCRAFT_CARRIER:
		required += 1
	if threat != null and threat.threat_score >= 60.0:
		required += 1
	return clampi(required, 1, mini(3, maxi(fleet_size - 1, 1)))


func evaluate_suitability(
		context: FleetMemberContext,
		threat: ShipUnit,
		protected_ship: ShipUnit
) -> float:
	var ship := context.get_ship()
	var threat_distance := ship.global_position.distance_to(
		threat.global_position
	)
	var protected_distance := ship.global_position.distance_to(
		protected_ship.global_position
	)
	var speed_score := ship.ship_data.max_speed_mps / 50.0 * 25.0
	var health_score := _get_health_ratio(ship) * 25.0
	var distance_score := maxf(1.0 - threat_distance / 8000.0, 0.0) * 30.0 \
		+ maxf(1.0 - protected_distance / 6000.0, 0.0) * 15.0
	var role_cost := 0.0
	match context.tactical_role:
		FleetMemberContext.TacticalRole.INTERCEPT:
			role_cost = -18.0
		FleetMemberContext.TacticalRole.ESCORT, \
				FleetMemberContext.TacticalRole.SCREEN:
			role_cost = 14.0
		FleetMemberContext.TacticalRole.LINE_COMBATANT:
			role_cost = 8.0
	var current_target := ship.get_ai_target() as ShipUnit
	if current_target != null \
			and is_instance_valid(current_target) \
			and current_target.is_alive() \
			and ship.combat.is_target_in_range(current_target):
		role_cost += 8.0
	return distance_score + speed_score + health_score - role_cost


func _get_health_ratio(ship: ShipUnit) -> float:
	return clampf(
		ship.health.current_health / maxf(ship.health.max_health, 1.0),
		0.0,
		1.0
	)
