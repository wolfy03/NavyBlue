extends RefCounted
class_name FleetEngagementPolicy


func build_target_decision(
		ranked: Array[FleetUnitObservation],
		current_primary: ShipUnit,
		current_is_valid: bool,
		current_is_out_of_range: bool,
		current_is_emergency: bool,
		lock_sec: float,
		emergency_targets: Array[ShipUnit],
		settings: FleetAISettings
) -> FleetTacticalDecision:
	var decision := FleetTacticalDecision.new()
	var selected := select_primary(
		ranked,
		current_primary,
		current_is_valid,
		current_is_out_of_range,
		current_is_emergency,
		lock_sec,
		settings
	)
	if selected != null:
		decision.primary_target = selected.get_ship()
		decision.primary_score = selected.raw_score
	decision.secondary_targets = select_secondary_targets(
		ranked,
		decision.primary_target,
		settings.secondary_target_limit
	)
	decision.emergency_targets = emergency_targets
	decision.reason = &"scheduled_target_evaluation"
	return decision


func select_secondary_targets(
		ranked: Array[FleetUnitObservation],
		primary_target: ShipUnit,
		limit: int
) -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	if limit <= 0:
		return result
	for observation in ranked:
		var candidate := observation.get_ship()
		if candidate == null or candidate == primary_target:
			continue
		result.append(candidate)
		if result.size() >= limit:
			break
	return result


func get_maximum_attackers(
		target: ShipUnit,
		fleet_size: int,
		emergency: bool,
		_settings: FleetAISettings
) -> int:
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
	normal_maximum = mini(normal_maximum, maxi(fleet_size, 1))
	return mini(maxi(normal_maximum + 1, 2), 4) \
		if emergency else normal_maximum


func select_primary(
		ranked: Array[FleetUnitObservation],
		current_primary: ShipUnit,
		current_is_valid: bool,
		current_is_out_of_range: bool,
		current_is_emergency: bool,
		lock_sec: float,
		settings: FleetAISettings
) -> FleetUnitObservation:
	if ranked.is_empty() or settings == null:
		return null
	var best := ranked[0]
	var best_ship := best.get_ship()
	var current: FleetUnitObservation
	for observation in ranked:
		if observation.get_ship() == current_primary:
			current = observation
			break
	if not current_is_valid or current == null or current_is_out_of_range:
		return best
	if best_ship == current_primary:
		return current
	var best_is_emergency := best.emergency
	if best_is_emergency and not current_is_emergency:
		return best
	var minimum_hold := settings.emergency_primary_hold_sec \
		if current_is_emergency else settings.primary_target_minimum_hold_sec
	var switch_ratio := settings.emergency_primary_switch_ratio \
		if current_is_emergency and best_is_emergency \
		else settings.primary_target_switch_ratio
	if lock_sec < minimum_hold \
			or best.raw_score <= current.raw_score * switch_ratio:
		return current
	return best


func build_member_order(
		ship: ShipUnit,
		context: FleetMemberContext
) -> FleetMemberOrder:
	var order := FleetMemberOrder.new()
	order.ship = ship
	order.target = context.get_assigned_target()
	order.destination = context.tactical_position \
		if context.tactical_position_valid else ship.global_position
	order.reason = StringName(
		FleetMemberContext.TacticalRole.keys()[int(context.tactical_role)]
	)
	match context.tactical_role:
		FleetMemberContext.TacticalRole.INTERCEPT:
			order.order_type = FleetMemberOrder.OrderType.FOCUS_FIRE
		FleetMemberContext.TacticalRole.DISENGAGE:
			order.order_type = FleetMemberOrder.OrderType.RETREAT
		FleetMemberContext.TacticalRole.SUPPORT:
			order.order_type = FleetMemberOrder.OrderType.REGROUP
		FleetMemberContext.TacticalRole.LINE_COMBATANT, \
				FleetMemberContext.TacticalRole.ESCORT, \
				FleetMemberContext.TacticalRole.SCREEN:
			order.order_type = FleetMemberOrder.OrderType.MAINTAIN_RANGE
		FleetMemberContext.TacticalRole.FLANKER:
			order.order_type = FleetMemberOrder.OrderType.APPROACH
		_:
			order.order_type = FleetMemberOrder.OrderType.HOLD
	return order
