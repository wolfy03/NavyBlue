extends SceneTree

var _failures: Array[String] = []
var _check_count := 0
var _arena: Node3D
var _provider_units: Array = []
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _ship_database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_broadside_heading_and_intercept_position()
	await _test_battlefield_incoming_attackers()
	await _test_limited_emergency_interceptors()
	await _test_stable_difficulty_error_and_primary_hysteresis()
	await _test_deterministic_roles_and_average_forward()
	await _test_boundary_side_switch()
	await _test_path_failure_cooldown_and_error_boundary()
	await _test_debug_throttle_and_empty_lifecycle()
	print("FLEET_AI_STABILIZATION checks=%d failures=%d" % [
		_check_count,
		_failures.size(),
	])
	for failure in _failures:
		push_error("FLEET AI STABILIZATION TEST: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_broadside_heading_and_intercept_position() -> void:
	_begin_arena()
	var bounds := _add_bounds()
	var line_ship := _spawn_ship("bb_ironwake", &"ally", Vector3(-3500.0, 0.0, 0.0))
	var target := _spawn_ship("bb_ironwake", &"enemy", Vector3(2500.0, 0.0, 0.0))
	line_ship.set_physics_process(false)
	target.set_physics_process(false)
	var solver := TacticalPositionSolver.new().setup(bounds)
	var line_result := solver.calculate_line_combat_position(
		line_ship,
		target,
		4800.0,
		1.0,
		900.0
	)
	_check(line_result.valid, "LINE_COMBATANT returns a valid tactical result")
	var radial := line_result.position - target.global_position
	radial.y = 0.0
	var target_direction := target.global_position - line_result.position
	target_direction.y = 0.0
	_check(
		absf(line_result.heading.normalized().dot(target_direction.normalized())) < 0.25,
		"LINE_COMBATANT heading is tangent instead of bow-on"
	)

	var line_context := FleetMemberContext.new().setup(line_ship)
	line_context.tactical_role = FleetMemberContext.TacticalRole.LINE_COMBATANT
	line_context.apply_tactical_result(line_result, target, 0.0)
	line_ship.on_fleet_tactical_context_changed(line_context)
	line_ship.global_position = line_result.position
	line_ship.set_ai_target(target)
	line_ship.ai.update_ai(
		line_ship,
		line_ship.movement,
		line_ship.navigation,
		line_ship.combat,
		line_ship.ship_data,
		0.1
	)
	var expected_rudder := line_ship.movement.get_rudder_to_direction(line_result.heading)
	_check(
		is_equal_approx(line_ship.movement.rudder_input, expected_rudder),
		"ship hull steering follows tactical heading at the broadside slot"
	)
	_check(
		line_ship.combat.has_aim_point
			and line_ship.combat.aim_point.is_equal_approx(target.global_position),
		"turret aim remains on the target while the hull follows the tangent"
	)
	_check(
		not line_ship.navigation.has_navigation_target,
		"broadside arrival does not recalculate an unchanged path"
	)

	var interceptor := _spawn_ship("dd_bluewind", &"ally", Vector3(-5000.0, 0.0, 1200.0))
	var protected := _spawn_ship("cv_seabastion", &"ally", Vector3(-4500.0, 0.0, 0.0))
	var threat := _spawn_ship("dd_bluewind", &"enemy", Vector3(1000.0, 0.0, 0.0))
	for ship in [interceptor, protected, threat]:
		ship.set_physics_process(false)
	threat.velocity = Vector3(-25.0, 0.0, 0.0)
	var intercept_distance := interceptor.get_navigation_safety_radius_m() \
		+ threat.get_navigation_safety_radius_m() \
		+ interceptor.ship_data.ai_role_profile.tactical_clearance_m \
		+ interceptor.ship_data.ai_role_profile.intercept_buffer_m
	var intercept_result := solver.calculate_intercept_position(
		interceptor,
		protected,
		threat,
		intercept_distance,
		2.0
	)
	var predicted_threat := threat.global_position + threat.velocity * 2.0
	var expected_direction := protected.global_position - predicted_threat
	expected_direction.y = 0.0
	var actual_direction := intercept_result.position - predicted_threat
	actual_direction.y = 0.0
	_check(
		intercept_result.valid
			and actual_direction.normalized().dot(expected_direction.normalized()) > 0.99,
		"INTERCEPT position lies between the predicted threat and protected ship"
	)
	_check(
		absf(actual_direction.length() - intercept_distance) < 1.0,
		"INTERCEPT position includes safety radii and tactical clearance"
	)

	var intercept_context := FleetMemberContext.new().setup(interceptor)
	intercept_context.tactical_role = FleetMemberContext.TacticalRole.INTERCEPT
	intercept_context.set_protected_ship(protected)
	intercept_context.set_assigned_target(threat)
	intercept_context.apply_tactical_result(intercept_result, threat, 0.0)
	interceptor.on_fleet_tactical_context_changed(intercept_context)
	interceptor.set_ai_target(threat)
	interceptor.ai.update_ai(
		interceptor,
		interceptor.movement,
		interceptor.navigation,
		interceptor.combat,
		interceptor.ship_data,
		0.1
	)
	_check(
		interceptor.navigation.has_navigation_target
			and interceptor.navigation.target_position.distance_to(intercept_result.position) < 1.0,
		"ShipAI follows the intercept point even while the threat is outside weapon range"
	)
	_check(
		interceptor.navigation.target_position.distance_to(threat.global_position) > 300.0,
		"ShipAI does not replace the intercept point with the threat center"
	)
	_check(
		interceptor.combat.is_target_in_range(threat),
		"ShipCombat range queries use the requested target instead of self-distance"
	)
	interceptor.targeting.request_immediate_evaluation()
	interceptor.targeting.update_targeting(0.0)
	var assigned_breakdown := interceptor.targeting.get_debug_score_breakdown(threat)
	_check(
		is_equal_approx(float(assigned_breakdown["tactical_assignment_score"]), 35.0),
		"INTERCEPT assigned threat receives the tactical combat-target bonus"
	)
	_end_arena()


func _test_battlefield_incoming_attackers() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	var scene := packed.instantiate() as BattleScene
	root.add_child(scene)
	await process_frame
	await physics_frame
	for fleet in scene.get_fleet_controllers():
		fleet.set_process(false)
	var carrier := _find_ship_by_class(
		scene.friendly_fleet_ai.get_alive_members(),
		ShipData.ShipClass.AIRCRAFT_CARRIER
	)
	for enemy in scene.enemy_fleet_ai.get_alive_members():
		enemy.set_physics_process(false)
		enemy.set_ai_target(carrier)
	_check(
		scene.get_incoming_attacker_count(carrier) == 3,
		"battlefield registry sums three attackers from a hostile fleet tracker"
	)
	_check(
		scene.get_incoming_attackers(carrier).size() == 3,
		"battlefield registry returns the actual incoming attackers"
	)
	var reinforcement := _ship_scene.instantiate() as ShipUnit
	var reinforcement_data := _ship_database.get_ship("dd_bluewind").duplicate(true) as ShipData
	reinforcement.setup(reinforcement_data, &"enemy", false, Color.WHITE)
	reinforcement.fleet_id = &"enemy_reinforcement"
	scene.ships_root.add_child(reinforcement)
	reinforcement.global_position = Vector3(1800.0, 0.0, 1800.0)
	reinforcement.set_physics_process(false)
	await process_frame
	reinforcement.set_ai_target(carrier)
	_check(
		scene.get_incoming_attacker_count(carrier) == 4,
		"incoming attacker lookup combines independent hostile fleet trackers"
	)
	var independent_counts: Array[int] = []
	for fleet in scene.get_fleet_controllers():
		if FactionRelations.are_hostile(fleet.team, carrier.team):
			independent_counts.append(fleet.assignment_tracker.get_attacker_count(carrier))
	independent_counts.sort()
	_check(
		independent_counts == [1, 3],
		"hostile fleets keep separate assignment counts while battlefield queries sum them"
	)
	var cruiser := _find_ship_by_class(
		scene.friendly_fleet_ai.get_alive_members(),
		ShipData.ShipClass.CRUISER
	)
	_check(
		scene.friendly_fleet_ai.get_protected_ship_score(carrier)
			> scene.friendly_fleet_ai.get_protected_ship_score(cruiser),
		"incoming attackers increase the protected-ship score"
	)
	var ally_alpha := _ship_scene.instantiate() as ShipUnit
	ally_alpha.setup(
		_ship_database.get_ship("dd_bluewind").duplicate(true) as ShipData,
		&"ally",
		false,
		Color.WHITE
	)
	ally_alpha.fleet_id = &"alpha"
	scene.ships_root.add_child(ally_alpha)
	var enemy_alpha := _ship_scene.instantiate() as ShipUnit
	enemy_alpha.setup(
		_ship_database.get_ship("dd_bluewind").duplicate(true) as ShipData,
		&"enemy",
		false,
		Color.WHITE
	)
	enemy_alpha.fleet_id = &"alpha"
	scene.ships_root.add_child(enemy_alpha)
	await process_frame
	var alpha_controllers: Array[FleetAIController] = []
	for fleet in scene.get_fleet_controllers():
		if fleet.fleet_id == &"alpha":
			alpha_controllers.append(fleet)
	_check(
		alpha_controllers.size() == 2
			and alpha_controllers[0].team != alpha_controllers[1].team,
		"identical fleet IDs on different teams create independent controllers"
	)
	var ally_alpha_controller := ally_alpha.get_fleet_controller()
	var enemy_alpha_controller := enemy_alpha.get_fleet_controller()
	ally_alpha_controller.set_process(false)
	ally_alpha_controller.empty_fleet_grace_sec = 0.0
	ally_alpha_controller.unregister_member(ally_alpha)
	ally_alpha_controller.update_fleet(0.1)
	await process_frame
	_check(
		is_instance_valid(enemy_alpha_controller)
			and scene.get_fleet_controllers().has(enemy_alpha_controller),
		"removing ALLY/alpha does not remove ENEMY/alpha"
	)
	scene.queue_free()
	await process_frame
	await physics_frame


func _test_limited_emergency_interceptors() -> void:
	_begin_arena()
	var bounds := _add_bounds()
	var fleet := _add_fleet(&"friendly", &"ally", bounds)
	var composition := [
		"cv_seabastion",
		"bb_ironwake",
		"cl_tidebreaker",
		"cl_tidebreaker",
		"dd_bluewind",
		"dd_bluewind",
	]
	var members: Array[ShipUnit] = []
	for index in composition.size():
		var ship := _spawn_ship(
			composition[index],
			&"ally",
			Vector3(-3500.0 + float(index % 3) * 450.0, 0.0, float(index / 3) * 500.0)
		)
		ship.set_physics_process(false)
		members.append(ship)
	var threat := _spawn_ship("dd_bluewind", &"enemy", Vector3(-900.0, 0.0, 0.0))
	threat.set_physics_process(false)
	_provider_units.assign(members)
	_provider_units.append(threat)
	for ship in members:
		ship.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
		fleet.register_member(ship)
	fleet.update_fleet(10.0)
	fleet.update_fleet(10.0)
	fleet.register_emergency_threat(threat, 45.0, &"capital_ship_proximity")
	fleet.update_fleet(5.0)
	var suitability_ship := members[2]
	suitability_ship.set_ai_target(null)
	var idle_suitability := float(fleet.call(
		&"_get_interceptor_suitability",
		suitability_ship,
		threat,
		members[0]
	))
	suitability_ship.set_ai_target(threat)
	var engaged_suitability := float(fleet.call(
		&"_get_interceptor_suitability",
		suitability_ship,
		threat,
		members[0]
	))
	_check(
		is_equal_approx(idle_suitability - engaged_suitability, 8.0),
		"an in-range current combat target adds the intended INTERCEPT role-change cost"
	)
	var intercept_count := _count_role(members, fleet, FleetMemberContext.TacticalRole.INTERCEPT)
	var screen_count := _count_role(members, fleet, FleetMemberContext.TacticalRole.SCREEN)
	var escort_count := _count_role(members, fleet, FleetMemberContext.TacticalRole.ESCORT)
	_check(
		intercept_count >= 1 and intercept_count <= 2,
		"a single destroyer threat receives only the required interceptors"
	)
	_check(
		screen_count >= 1 and escort_count >= 1,
		"SCREEN and ESCORT roles remain staffed during a limited intercept"
	)
	for ship in members:
		var context := fleet.get_member_context(ship)
		if context.tactical_role != FleetMemberContext.TacticalRole.INTERCEPT:
			continue
		_check(
			context.temporary_role_reason == &"emergency_intercept"
				and context.tactical_position_valid,
			"interceptors retain temporary-role metadata and a valid block position"
		)
		_check(
			context.tactical_position.distance_to(threat.global_position)
				> ship.get_navigation_safety_radius_m(),
			"fleet intercept positions do not target the threat center"
		)
	var second_threat := _spawn_ship(
		"dd_bluewind",
		&"enemy",
		Vector3(-1200.0, 0.0, 1800.0)
	)
	second_threat.set_physics_process(false)
	_provider_units.append(second_threat)
	fleet.register_emergency_threat(second_threat, 40.0, &"capital_ship_proximity")
	fleet.call(&"_update_tactical_positions")
	var assigned_threat_ids: Dictionary = {}
	for ship in members:
		var context := fleet.get_member_context(ship)
		if context.tactical_role != FleetMemberContext.TacticalRole.INTERCEPT:
			continue
		var assigned_threat := context.get_assigned_target()
		if assigned_threat != null:
			assigned_threat_ids[assigned_threat.get_instance_id()] = true
	_check(
		_count_role(members, fleet, FleetMemberContext.TacticalRole.INTERCEPT) <= 3,
		"multiple emergencies still respect the fleet-wide interceptor cap"
	)
	_check(
		assigned_threat_ids.size() == 2,
		"interceptors are distributed across simultaneous emergency threats"
	)
	var emergency_contexts := fleet.get(&"_emergency_threats") as Dictionary
	for threat_context_value in emergency_contexts.values():
		var threat_context := threat_context_value as FleetThreatContext
		threat_context.expires_time_sec = 0.0
	fleet.call(&"_cleanup_emergency_threats")
	fleet.call(&"_assign_tactical_roles", true)
	_check(
		_count_role(members, fleet, FleetMemberContext.TacticalRole.INTERCEPT) == 0,
		"temporary INTERCEPT roles end after the emergency expires"
	)
	_check(
		_count_role(members, fleet, FleetMemberContext.TacticalRole.SCREEN) >= 1
			and _count_role(members, fleet, FleetMemberContext.TacticalRole.ESCORT) >= 1,
		"former interceptors return through normal role scoring"
	)
	_end_arena()


func _test_stable_difficulty_error_and_primary_hysteresis() -> void:
	_begin_arena()
	var bounds := _add_bounds()
	var easy := load("res://resources/ai_difficulty/easy.tres") as AIDifficultyProfile
	var fleet := FleetAIController.new()
	_arena.add_child(fleet)
	fleet.setup(
		&"easy_fleet",
		&"ally",
		Callable(self, &"_get_provider_units"),
		bounds,
		easy
	)
	fleet.set_process(false)
	var member := _spawn_ship("bb_ironwake", &"ally", Vector3(-3500.0, 0.0, 0.0))
	var target_a := _spawn_ship("cl_tidebreaker", &"enemy", Vector3(3000.0, 0.0, -300.0))
	var target_b := _spawn_ship("cl_tidebreaker", &"enemy", Vector3(3000.0, 0.0, 300.0))
	for ship in [member, target_a, target_b]:
		ship.set_physics_process(false)
	_provider_units = [member, target_a, target_b]
	member.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	fleet.register_member(member)
	fleet.update_fleet(10.0)
	fleet.update_fleet(10.0)
	var context := fleet.get_member_context(member)
	var first_error := context.tactical_error_offset
	var first_expiry := context.tactical_error_expire_sec
	fleet.call(&"_update_tactical_positions")
	_check(
		context.tactical_error_offset.is_equal_approx(first_error)
			and is_equal_approx(context.tactical_error_expire_sec, first_expiry),
		"difficulty position error remains stable across normal tactical updates"
	)

	var original_primary := fleet.get_primary_target()
	var challenger := target_b if original_primary == target_a else target_a
	challenger.ship_data.strategic_value = 3.0
	fleet.set(&"_primary_target_lock_sec", 1.0)
	fleet.call(&"_evaluate_fleet_targets")
	_check(
		fleet.get_primary_target() == original_primary,
		"primary hysteresis holds a live target before the minimum hold time"
	)
	fleet.set(&"_primary_target_lock_sec", 10.0)
	fleet.call(&"_evaluate_fleet_targets")
	_check(
		fleet.get_primary_target() == challenger,
		"primary hysteresis switches after hold time when the ratio is exceeded"
	)
	challenger.health.current_health = 0.0
	fleet.call(&"_refresh_hostile_candidate_cache")
	fleet.call(&"_evaluate_fleet_targets")
	_check(
		fleet.get_primary_target() == original_primary,
		"destroying the primary target permits an immediate replacement"
	)
	_end_arena()


func _test_deterministic_roles_and_average_forward() -> void:
	_begin_arena()
	var bounds := _add_bounds()
	var fleet := _add_fleet(&"stable_roles", &"ally", bounds)
	var composition := [
		"cv_seabastion",
		"bb_ironwake",
		"cl_tidebreaker",
		"cl_tidebreaker",
		"dd_bluewind",
		"dd_bluewind",
	]
	var members: Array[ShipUnit] = []
	for index in composition.size():
		var ship := _spawn_ship(
			composition[index],
			&"ally",
			Vector3(-3000.0 + float(index) * 250.0, 0.0, float(index % 2) * 400.0)
		)
		ship.set_physics_process(false)
		members.append(ship)
	_provider_units.assign(members)
	for ship in members:
		fleet.register_member(ship)
	var first_roles := _capture_roles(members, fleet)
	for ship in members:
		fleet.unregister_member(ship)
	var reversed := members.duplicate()
	reversed.reverse()
	for ship in reversed:
		fleet.register_member(ship)
	var second_roles := _capture_roles(members, fleet)
	_check(first_roles == second_roles, "role assignment is independent of registration order")

	var first := members[1]
	var second := members[2]
	for ship in members:
		fleet.unregister_member(ship)
	fleet.register_member(first)
	fleet.register_member(second)
	first.rotation.y = 0.0
	second.rotation.y = PI
	first.velocity = Vector3(12.0, 0.0, 0.0)
	second.velocity = Vector3(12.0, 0.0, 0.0)
	fleet.call(&"_update_fleet_geometry")
	_check(
		fleet.fleet_average_forward.dot(Vector3.RIGHT) > 0.95,
		"fleet average forward falls back to current average velocity"
	)
	_end_arena()


func _test_boundary_side_switch() -> void:
	_begin_arena()
	var settings := preload("res://resources/settings/default_battlefield_settings.tres").duplicate(true) \
		as BattlefieldSettings
	settings.map_size_m = Vector2(20000.0, 20000.0)
	var bounds := BattlefieldBounds.new()
	bounds.settings = settings
	_arena.add_child(bounds)
	var owner := _spawn_ship("bb_ironwake", &"ally", Vector3(7000.0, 0.0, 9000.0))
	var target := _spawn_ship("bb_ironwake", &"enemy", Vector3(9000.0, 0.0, 9000.0))
	owner.set_physics_process(false)
	target.set_physics_process(false)
	var solver := TacticalPositionSolver.new().setup(bounds)
	var held_side := solver.calculate_line_combat_position(
		owner,
		target,
		3000.0,
		-1.0,
		2000.0,
		false
	)
	var switched_side := solver.calculate_line_combat_position(
		owner,
		target,
		3000.0,
		-1.0,
		2000.0,
		true
	)
	_check(
		held_side.was_clamped and not held_side.requires_side_switch,
		"side hold keeps the current side and reports boundary clamping"
	)
	_check(
		switched_side.requires_side_switch
			and switched_side.side_sign > 0.0
			and switched_side.clamp_distance_m < held_side.clamp_distance_m,
		"solver requests the less-clamped opposite broadside"
	)
	_end_arena()


func _test_path_failure_cooldown_and_error_boundary() -> void:
	_begin_arena()
	var bounds := _add_bounds()
	var easy := load("res://resources/ai_difficulty/easy.tres") as AIDifficultyProfile
	var fleet := FleetAIController.new()
	_arena.add_child(fleet)
	fleet.setup(
		&"failure_test",
		&"ally",
		Callable(self, &"_get_provider_units"),
		bounds,
		easy
	)
	fleet.set_process(false)
	var ship := _spawn_ship("bb_ironwake", &"ally", Vector3(8500.0, 0.0, 0.0))
	var target := _spawn_ship("bb_ironwake", &"enemy", Vector3(9000.0, 0.0, 0.0))
	for unit in [ship, target]:
		unit.set_physics_process(false)
	_provider_units = [ship, target]
	ship.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	fleet.register_member(ship)
	var context := fleet.get_member_context(ship)
	context.tactical_position = Vector3(9200.0, 0.0, 0.0)
	context.tactical_heading = Vector3.RIGHT
	context.tactical_position_valid = true
	context.tactical_heading_valid = true
	ship.on_fleet_tactical_context_changed(context)
	ship.navigation.set_navigation_target(context.tactical_position)
	fleet.report_tactical_path_failure(ship)
	var now_sec := float(Time.get_ticks_msec()) * 0.001
	_check(
		not context.tactical_position_valid
			and not context.tactical_heading_valid
			and context.tactical_position_invalid_until_sec > now_sec,
		"path failure invalidates both tactical position and heading for a cooldown"
	)
	_check(
		not ship.navigation.has_navigation_target,
		"path failure clears the failed navigation target immediately"
	)
	ship.navigation.set_navigation_target(Vector3(9200.0, 0.0, 0.0))
	ship.ai.update_ai(
		ship,
		ship.movement,
		ship.navigation,
		ship.combat,
		ship.ship_data,
		0.1
	)
	_check(
		not ship.navigation.has_navigation_target
			and is_zero_approx(ship.movement.engine_output),
		"ShipAI does not re-request a stale tactical position during cooldown"
	)

	var result := TacticalPositionResult.new()
	result.valid = true
	result.position = Vector3(9700.0, 0.0, 0.0)
	context.tactical_role = FleetMemberContext.TacticalRole.LINE_COMBATANT
	context.tactical_side_sign = 1.0
	context.tactical_error_offset = Vector3(350.0, 0.0, 0.0)
	context.tactical_error_expire_sec = now_sec + 1000.0
	context.tactical_error_target_instance_id = target.get_instance_id()
	context.tactical_error_role = context.tactical_role
	context.tactical_error_side_sign = context.tactical_side_sign
	context.tactical_error_profile_id = easy.difficulty_id
	fleet.call(
		&"_apply_difficulty_error_with_bounds",
		result,
		ship,
		context,
		target,
		now_sec
	)
	_check(
		bounds.is_inside_bounds(result.position)
			and result.position.distance_to(Vector3(9700.0, 0.0, 0.0)) < 1.0,
		"boundary-unsafe difficulty error is reduced without displacing the base slot"
	)
	fleet.set(&"_primary_target_ref", weakref(target))
	fleet.register_emergency_threat(target, 50.0, &"cache_validation")
	target.health.current_health = 0.0
	_check(
		fleet.get_primary_target() == null
			and fleet.get_emergency_targets().is_empty()
			and (fleet.get(&"_emergency_target_ids") as Dictionary).is_empty(),
		"destroyed primary and emergency targets are removed from public results and caches"
	)
	_end_arena()


func _test_debug_throttle_and_empty_lifecycle() -> void:
	_begin_arena()
	var bounds := _add_bounds()
	var fleet := _add_fleet(&"lifecycle", &"ally", bounds)
	var member := _spawn_ship("dd_bluewind", &"ally", Vector3.ZERO)
	member.set_physics_process(false)
	_provider_units = [member]
	fleet.register_member(member)
	fleet.debug_enabled = true
	fleet.debug_update_interval_sec = 0.4
	fleet.debug_snapshot_update_count = 0
	fleet.update_fleet(0.1)
	fleet.update_fleet(0.1)
	fleet.update_fleet(0.1)
	_check(
		fleet.debug_snapshot_update_count == 0,
		"debug snapshots are not rebuilt every frame"
	)
	fleet.update_fleet(0.11)
	_check(
		fleet.debug_snapshot_update_count == 1,
		"debug snapshot refreshes at the configured interval"
	)
	var empty_events := [0]
	fleet.became_empty.connect(
		func(_team: StringName, _fleet_id: StringName) -> void:
			empty_events[0] += 1
	)
	fleet.empty_fleet_grace_sec = 1.0
	fleet.unregister_member(member)
	fleet.update_fleet(0.6)
	fleet.register_member(member)
	fleet.update_fleet(0.5)
	_check(
		empty_events[0] == 0,
		"reinforcement before the grace deadline reactivates the existing fleet"
	)
	fleet.unregister_member(member)
	fleet.update_fleet(0.6)
	fleet.update_fleet(0.5)
	_check(
		empty_events[0] == 1
			and fleet.assignment_tracker.get_assignment_count() == 0
			and fleet.get_primary_target() == null
			and fleet.get_emergency_targets().is_empty(),
		"empty fleet emits once after accumulated grace time and clears target caches"
	)
	_end_arena()


func _begin_arena() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var aircraft_root := Node3D.new()
	aircraft_root.name = "Aircraft"
	aircraft_root.add_to_group(&"aircraft_root")
	_arena.add_child(aircraft_root)
	_provider_units.clear()


func _end_arena() -> void:
	_provider_units.clear()
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	await process_frame
	await physics_frame
	_arena = null


func _add_bounds() -> BattlefieldBounds:
	var bounds := BattlefieldBounds.new()
	_arena.add_child(bounds)
	return bounds


func _add_fleet(
		fleet_id: StringName,
		team: StringName,
		bounds: BattlefieldBounds
) -> FleetAIController:
	var fleet := FleetAIController.new()
	_arena.add_child(fleet)
	fleet.setup(fleet_id, team, Callable(self, &"_get_provider_units"), bounds)
	fleet.set_process(false)
	return fleet


func _spawn_ship(
		ship_id: String,
		team: StringName,
		position: Vector3
) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	var source_data := _ship_database.get_ship(ship_id)
	ship.setup(source_data.duplicate(true) as ShipData, team, false, Color.WHITE)
	_arena.add_child(ship)
	ship.global_position = position
	return ship


func _get_provider_units() -> Array:
	var result: Array = []
	for ship in _provider_units:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			result.append(ship)
	return result


func _find_ship_by_class(
		ships: Array[ShipUnit],
		ship_class: ShipData.ShipClass
) -> ShipUnit:
	for ship in ships:
		if ship.ship_data.ship_class == ship_class:
			return ship
	return null


func _count_role(
		members: Array[ShipUnit],
		fleet: FleetAIController,
		role: FleetMemberContext.TacticalRole
) -> int:
	var count := 0
	for ship in members:
		if fleet.get_member_context(ship).tactical_role == role:
			count += 1
	return count


func _capture_roles(
		members: Array[ShipUnit],
		fleet: FleetAIController
) -> Dictionary:
	var result: Dictionary = {}
	for ship in members:
		result[ship.get_instance_id()] = fleet.get_member_context(ship).tactical_role
	return result


func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(description)
