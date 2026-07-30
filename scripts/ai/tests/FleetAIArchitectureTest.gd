extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var controller := FleetAIController.new()
	var controller_properties: Dictionary = {}
	for property in controller.get_property_list():
		controller_properties[StringName(property.name)] = true
	for moved_name in [
		&"secondary_target_limit",
		&"nearby_candidate_radius_m",
		&"emergency_hold_sec",
		&"role_minimum_hold_sec",
		&"empty_fleet_grace_sec",
		&"debug_update_interval_sec",
	]:
		_check(
			not controller_properties.has(moved_name),
			"controller no longer owns %s" % moved_name
		)

	var settings := FleetAISettings.new()
	_check(settings.validate().is_empty(), "default settings validate")
	settings.fleet_update_interval_sec = 0.0
	_check(
		not settings.validate().is_empty(),
		"invalid scheduling settings fail validation"
	)

	var difficulty := AIDifficultyProfile.new()
	var difficulty_properties: Dictionary = {}
	for property in difficulty.get_property_list():
		difficulty_properties[StringName(property.name)] = true
	_check(
		not difficulty_properties.has(&"fleet_update_interval_sec")
			and difficulty_properties.has(
				&"fleet_update_interval_multiplier"
			),
		"difficulty owns multipliers rather than base cadence"
	)

	var recommendation := FleetTargetRecommendation.new()
	recommendation.score = 12.0
	_check(
		recommendation.score == 12.0
			and recommendation is FleetTargetRecommendation,
		"target recommendation is typed"
	)
	var decision := FleetTacticalDecision.new()
	var order := FleetMemberOrder.new()
	decision.member_orders.append(order)
	_check(
		decision.member_orders[0] == order,
		"tactical decisions contain typed member orders"
	)

	var policy := FleetEngagementPolicy.new()
	_check(
		policy.select_secondary_targets(
			[],
			null,
			0
		).is_empty(),
		"zero secondary target limit produces no targets"
	)
	var target := ShipUnit.new()
	target.ship_data = ShipData.new()
	target.ship_data.ship_class = ShipData.ShipClass.BATTLESHIP
	_check(
		policy.get_maximum_attackers(target, 6, false, settings) == 4
			and policy.get_maximum_attackers(
				target,
				6,
				true,
				settings
			) == 4,
		"engagement policy preserves battleship attacker limits"
	)
	var context := FleetMemberContext.new().setup(target)
	context.tactical_role = FleetMemberContext.TacticalRole.SUPPORT
	context.tactical_position = Vector3(10.0, 0.0, 20.0)
	context.tactical_position_valid = true
	var policy_order := policy.build_member_order(target, context)
	_check(
		policy_order.order_type == FleetMemberOrder.OrderType.REGROUP
			and policy_order.ship == target,
		"engagement policy builds typed member orders"
	)
	target.free()
	controller.free()
	print("FLEET_AI_ARCHITECTURE_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("FLEET AI ARCHITECTURE: %s" % label)
