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
	await _test_three_vs_three_battle_scene()
	await _test_damage_normalization_and_emergency_lock()
	await _test_independent_fleet_trackers()
	await _test_six_vs_six_roles_and_positions()
	print("FLEET_AI_STAGE3 checks=%d failures=%d" % [_check_count, _failures.size()])
	for failure in _failures:
		push_error("FLEET AI STAGE3 TEST: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_three_vs_three_battle_scene() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	var scene := packed.instantiate() as BattleScene
	root.add_child(scene)
	await process_frame
	await physics_frame
	var fleets := scene.get_fleet_controllers()
	_check(
		fleets.size() == 3,
		"battle scene separates player, ally, and enemy controllers by team and fleet ID"
	)
	var player_fleet: FleetAIController
	for fleet in fleets:
		if fleet.team == FactionRelations.PLAYER:
			player_fleet = fleet
	_check(
		player_fleet != null
			and player_fleet.get_alive_members().size() == 1
			and scene.friendly_fleet_ai.get_alive_members().size() == 2
			and scene.enemy_fleet_ai.get_alive_members().size() == 3,
		"3v3 participants register in the correct fleet"
	)
	for fleet in fleets:
		fleet.set_process(false)
		fleet.update_fleet(10.0)
		fleet.update_fleet(10.0)

	var friendly_cruiser := _find_ship_by_class(
		scene.friendly_fleet_ai.get_alive_members(),
		ShipData.ShipClass.CRUISER
	)
	var friendly_carrier := _find_ship_by_class(
		scene.friendly_fleet_ai.get_alive_members(),
		ShipData.ShipClass.AIRCRAFT_CARRIER
	)
	var enemy_battleship := _find_ship_by_class(
		scene.enemy_fleet_ai.get_alive_members(),
		ShipData.ShipClass.BATTLESHIP
	)
	_check(
		scene.friendly_fleet_ai.get_member_context(friendly_cruiser).tactical_role
			== FleetMemberContext.TacticalRole.ESCORT,
		"friendly cruiser escorts the high-value carrier when needed"
	)
	var carrier_context := scene.friendly_fleet_ai.get_member_context(friendly_carrier)
	_check(
		carrier_context.tactical_role == FleetMemberContext.TacticalRole.SUPPORT
			and carrier_context.tactical_position_valid,
		"carrier receives a valid SUPPORT rear position"
	)
	_check(
		carrier_context.tactical_position.distance_to(
			scene.friendly_fleet_ai.fleet_center
		) >= 1500.0,
		"carrier support slot remains behind the fleet instead of stopping in place"
	)
	var battleship_context := scene.enemy_fleet_ai.get_member_context(enemy_battleship)
	var line_target := enemy_battleship.get_ai_target() as ShipUnit
	if line_target == null:
		line_target = scene.enemy_fleet_ai.get_primary_target()
	var radial := enemy_battleship.global_position - line_target.global_position
	radial.y = 0.0
	var tactical_offset := battleship_context.tactical_position - line_target.global_position
	tactical_offset.y = 0.0
	var lateral_component := absf(
		Vector2(radial.normalized().x, radial.normalized().z).cross(
			Vector2(tactical_offset.x, tactical_offset.z)
		)
	)
	_check(
		battleship_context.tactical_role
			== FleetMemberContext.TacticalRole.LINE_COMBATANT
			and lateral_component >= 500.0,
		"battleship line position includes a broadside tangent offset"
	)
	_check(
		not scene.player_ship.navigation.has_navigation_target,
		"Fleet AI does not issue movement commands to the player-controlled ship"
	)
	_check(
		scene.enemy_fleet_ai.get_primary_target() != scene.player_ship,
		"enemy fleet policy does not hard-code the player as primary target"
	)

	var cleanup_before := scene.enemy_fleet_ai.assignment_tracker.cleanup_count
	for ship in scene.enemies:
		ship.targeting.request_immediate_evaluation()
		ship.targeting.update_targeting(0.0)
	_check(
		scene.enemy_fleet_ai.assignment_tracker.cleanup_count == cleanup_before,
		"individual target evaluations never run fleet-wide tracker cleanup"
	)
	scene.enemy_fleet_ai.update_fleet(2.0)
	_check(
		scene.enemy_fleet_ai.assignment_tracker.cleanup_count == cleanup_before + 1,
		"fleet coordinator performs tracker cleanup once on its interval"
	)
	var event_bus: Node = root.get_node("EventBus")
	var damage_connections: Array = event_bus.ship_damaged.get_connections()
	_check(
		damage_connections.size() == 3,
		"only the three team-separated fleet coordinators subscribe to global damage"
	)
	scene.queue_free()
	await process_frame
	await physics_frame


func _test_damage_normalization_and_emergency_lock() -> void:
	_begin_arena()
	var destroyer := _spawn_ship("dd_bluewind", &"ally", Vector3.ZERO)
	var battleship := _spawn_ship("bb_ironwake", &"ally", Vector3(0.0, 0.0, 300.0))
	var attacker := _spawn_ship("dd_bluewind", &"enemy", Vector3(5000.0, 0.0, 0.0))
	for ship in [destroyer, battleship, attacker]:
		ship.set_physics_process(false)
	_provider_units = [destroyer, battleship, attacker]
	for victim in [destroyer, battleship]:
		victim.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
		victim.targeting.register_damage_source(attacker, 50.0)
	var destroyer_score := float(
		destroyer.targeting.get_debug_score_breakdown(attacker)["recent_damage_score"]
	)
	var battleship_score := float(
		battleship.targeting.get_debug_score_breakdown(attacker)["recent_damage_score"]
	)
	_check(
		destroyer_score > battleship_score,
		"equal raw damage scores higher against the lower-HP destroyer"
	)
	_check(
		destroyer_score <= destroyer.ship_data.ai_role_profile.maximum_recent_self_damage_score
			and battleship_score
				<= battleship.ship_data.ai_role_profile.maximum_recent_self_damage_score,
		"normalized recent self-damage scores respect role caps"
	)

	var emergency_owner := destroyer
	var emergency_a := _spawn_ship("dd_bluewind", &"enemy", Vector3(280.0, 0.0, 0.0))
	var emergency_b := _spawn_ship("dd_bluewind", &"enemy", Vector3(-290.0, 0.0, 0.0))
	emergency_a.set_physics_process(false)
	emergency_b.set_physics_process(false)
	_provider_units = [emergency_owner, emergency_a, emergency_b]
	emergency_owner.set_ai_target(emergency_a)
	for _evaluation in 2:
		emergency_owner.targeting.request_immediate_evaluation()
		emergency_owner.targeting.update_targeting(1.0)
	_check(
		emergency_owner.get_ai_target() == emergency_a,
		"emergency target lock prevents one-second oscillation between close threats"
	)
	emergency_a.queue_free()
	await process_frame
	emergency_owner.targeting.request_immediate_evaluation()
	emergency_owner.targeting.update_targeting(0.0)
	_check(
		emergency_owner.get_ai_target() == emergency_b,
		"removing an emergency target immediately selects the remaining threat"
	)
	_end_arena()


func _test_independent_fleet_trackers() -> void:
	_begin_arena()
	var target := _spawn_ship("bb_ironwake", &"enemy", Vector3.ZERO)
	var attacker_a := _spawn_ship("dd_bluewind", &"ally", Vector3(-1000.0, 0.0, 0.0))
	var attacker_b := _spawn_ship("cl_tidebreaker", &"ally", Vector3(-1200.0, 0.0, 0.0))
	var attacker_c := _spawn_ship("dd_bluewind", &"ally", Vector3(1000.0, 0.0, 0.0))
	var tracker_a := FleetTargetAssignmentTracker.new()
	var tracker_b := FleetTargetAssignmentTracker.new()
	tracker_a.assign(attacker_a, target)
	tracker_a.assign(attacker_b, target)
	tracker_b.assign(attacker_c, target)
	_check(
		tracker_a.get_attacker_count(target) == 2
			and tracker_b.get_attacker_count(target) == 1,
		"independent fleets count attackers on the same target separately"
	)
	tracker_a.clear_all()
	_check(
		tracker_b.get_attacker_count(target) == 1,
		"clearing one fleet tracker does not alter another fleet"
	)
	_end_arena()


func _test_six_vs_six_roles_and_positions() -> void:
	_begin_arena()
	var bounds := BattlefieldBounds.new()
	_arena.add_child(bounds)
	var fleet_a := FleetAIController.new()
	var fleet_b := FleetAIController.new()
	_arena.add_child(fleet_a)
	_arena.add_child(fleet_b)
	fleet_a.setup(&"fleet_a", &"ally", Callable(self, &"_get_provider_units"), bounds)
	fleet_b.setup(&"fleet_b", &"enemy", Callable(self, &"_get_provider_units"), bounds)
	fleet_a.set_process(false)
	fleet_b.set_process(false)

	var composition := [
		"bb_ironwake",
		"bb_ironwake",
		"cl_tidebreaker",
		"cl_tidebreaker",
		"dd_bluewind",
		"dd_bluewind",
	]
	var members_a: Array[ShipUnit] = []
	var members_b: Array[ShipUnit] = []
	for index in composition.size():
		var member_a := _spawn_ship(
			composition[index],
			&"ally",
			Vector3(-3500.0 + float(index % 3) * 400.0, 0.0, float(index / 3) * 500.0)
		)
		var member_b := _spawn_ship(
			composition[index],
			&"enemy",
			Vector3(3500.0 - float(index % 3) * 400.0, 0.0, float(index / 3) * 500.0)
		)
		member_a.set_physics_process(false)
		member_b.set_physics_process(false)
		members_a.append(member_a)
		members_b.append(member_b)
	_provider_units.assign(members_a)
	_provider_units.append_array(members_b)
	for member in members_a:
		member.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
		fleet_a.register_member(member)
	for member in members_b:
		member.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
		fleet_b.register_member(member)
	fleet_a.update_fleet(10.0)
	fleet_b.update_fleet(10.0)
	fleet_a.update_fleet(10.0)
	fleet_b.update_fleet(10.0)

	var role_counts: Dictionary = {}
	for member in members_a:
		var context := fleet_a.get_member_context(member)
		role_counts[context.tactical_role] = int(
			role_counts.get(context.tactical_role, 0)
		) + 1
		_check(context.tactical_position_valid, "6v6 member receives a tactical position")
	_check(
		int(role_counts.get(FleetMemberContext.TacticalRole.LINE_COMBATANT, 0)) >= 3,
		"battleships and one cruiser form the line"
	)
	_check(
		int(role_counts.get(FleetMemberContext.TacticalRole.ESCORT, 0)) == 1,
		"cruiser roles split between line and escort"
	)
	_check(
		int(role_counts.get(FleetMemberContext.TacticalRole.SCREEN, 0)) == 1
			and int(role_counts.get(FleetMemberContext.TacticalRole.FLANKER, 0)) == 1,
		"destroyers split between SCREEN and FLANKER"
	)
	for member in members_a:
		member.targeting.request_immediate_evaluation()
		member.targeting.update_targeting(0.0)
	var attacker_limits_respected := true
	for target in members_b:
		if fleet_a.assignment_tracker.get_attacker_count(target) \
				> fleet_a.get_maximum_attackers_for_target(target):
			attacker_limits_respected = false
	_check(
		attacker_limits_respected,
		"fleet recommendations and penalties respect class attacker limits"
	)
	_end_arena()


func _begin_arena() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_provider_units.clear()


func _end_arena() -> void:
	_provider_units.clear()
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	await process_frame
	await physics_frame
	_arena = null


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


func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(description)
