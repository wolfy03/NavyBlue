extends RefCounted
class_name FleetRoleSuitabilityPolicy


func evaluate(
		member: FleetMemberContext,
		role: FleetMemberContext.TacticalRole,
		protected_ship: ShipUnit,
		preserve_existing_role: bool,
		_settings: FleetAISettings,
		_difficulty: AIDifficultyProfile
) -> FleetRoleSuitabilityResult:
	var result := FleetRoleSuitabilityResult.new()
	result.role = role
	if member == null:
		result.reason = &"missing_member_context"
		return result
	var ship := member.get_ship()
	result.ship = ship
	if ship == null or not is_instance_valid(ship) \
			or ship.ship_data == null or ship.health == null:
		result.reason = &"invalid_ship"
		return result
	var score := _get_health_ratio(ship) * 25.0
	if protected_ship != null:
		score += maxf(
			1.0 - ship.global_position.distance_to(
				protected_ship.global_position
			) / 8000.0,
			0.0
		) * 25.0
	if role == FleetMemberContext.TacticalRole.SCREEN:
		score += ship.ship_data.max_speed_mps / 50.0 * 30.0
	elif role == FleetMemberContext.TacticalRole.ESCORT \
			and ship.ship_data.ship_class == ShipData.ShipClass.CRUISER:
		score += 20.0
	if preserve_existing_role and (
		member.tactical_role == role or (
			member.tactical_role == FleetMemberContext.TacticalRole.INTERCEPT
			and member.previous_tactical_role == role
	)):
		score += 18.0
	if member.tactical_position_valid \
			and ship.global_position.distance_squared_to(
				member.tactical_position
			) < 500.0 * 500.0:
		score += 6.0
	result.score = score
	result.suitable = true
	result.reason = &"role_suitability"
	return result


func select_best(
		contexts: Array[FleetMemberContext],
		role: FleetMemberContext.TacticalRole,
		protected_ship: ShipUnit,
		preserve_existing_role: bool,
		settings: FleetAISettings,
		difficulty: AIDifficultyProfile
) -> FleetRoleAssignment:
	var assignment := FleetRoleAssignment.new()
	assignment.role = role
	assignment.reason = &"no_suitable_member"
	for context in contexts:
		var result := evaluate(
			context,
			role,
			protected_ship,
			preserve_existing_role,
			settings,
			difficulty
		)
		if not result.suitable:
			continue
		if assignment.ship == null \
				or result.score > assignment.score \
				or (
					is_equal_approx(result.score, assignment.score)
					and result.ship.get_instance_id() \
						< assignment.ship.get_instance_id()
				):
			assignment.ship = result.ship
			assignment.score = result.score
			assignment.reason = result.reason
	return assignment


func _get_health_ratio(ship: ShipUnit) -> float:
	return clampf(
		ship.health.current_health / maxf(ship.health.max_health, 1.0),
		0.0,
		1.0
	)
