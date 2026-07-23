extends SceneTree

var _failures: Array[String] = []
var _check_count := 0
var _observed_pursuit_updates := 0
var _observed_path_calculations := 0
var _provider_units: Array = []
var _arena: Node3D
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _ship_database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_battle_registry_and_team_relations()
	await _test_retargeting_and_pursuit_throttling()
	await _test_class_ranges_and_carrier_behavior()
	print(
		"AI_TARGETING checks=%d failures=%d pursuit_updates=%d path_calculations=%d" % [
			_check_count,
			_failures.size(),
			_observed_pursuit_updates,
			_observed_path_calculations,
		]
	)
	for failure in _failures:
		push_error("AI TARGETING TEST: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_battle_registry_and_team_relations() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	var scene := packed.instantiate() as BattleScene
	root.add_child(scene)
	await process_frame
	await physics_frame
	_check(scene.get_battle_units().size() == 6, "BattleScene caches all initial participants")
	_check(
		FactionRelations.are_hostile(&"player", &"enemy")
			and FactionRelations.are_hostile(&"ally", &"enemy"),
		"player and ally are hostile to enemy"
	)
	_check(
		not FactionRelations.are_hostile(&"player", &"ally")
			and not FactionRelations.are_hostile(&"enemy", &"enemy")
			and not FactionRelations.are_hostile(&"neutral", &"enemy"),
		"friendly, same-team, and neutral relations are non-hostile"
	)
	for _frame in 40:
		await physics_frame
	var all_ai_targets_hostile := true
	for ship_value in scene.allies + scene.enemies:
		var ship := ship_value as ShipUnit
		if ship == null or ship.get_ai_target() == null or not ship.is_hostile_to(ship.get_ai_target()):
			all_ai_targets_hostile = false
	_check(all_ai_targets_hostile, "all AI ships independently acquire a hostile target")

	var enemy := scene.enemies[0] as ShipUnit
	var nearby_ally := scene.allies[0] as ShipUnit
	nearby_ally.global_position = enemy.global_position + Vector3(120.0, 0.0, 0.0)
	enemy.targeting.clear_target()
	enemy.targeting.request_immediate_evaluation()
	await physics_frame
	_check(
		enemy.get_ai_target() != null and enemy.is_hostile_to(enemy.get_ai_target()),
		"enemy threat selector evaluates hostile player-side ships"
	)
	scene.queue_free()
	await process_frame
	await physics_frame


func _test_retargeting_and_pursuit_throttling() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var hunter := _spawn_ship("dd_bluewind", &"ally", Vector3(-8000.0, 0.0, 0.0))
	var first_enemy := _spawn_ship("dd_bluewind", &"enemy", Vector3(8000.0, 0.0, 0.0))
	var fallback_enemy := _spawn_ship("cl_tidebreaker", &"enemy", Vector3(9000.0, 0.0, 1000.0))
	var same_team := _spawn_ship("dd_bluewind", &"ally", Vector3(-7900.0, 0.0, 0.0))
	var neutral := _spawn_ship("dd_bluewind", &"neutral", Vector3(-7950.0, 0.0, 0.0))
	_provider_units = [hunter, first_enemy, fallback_enemy, same_team, neutral]
	for ship_value in _provider_units:
		var ship := ship_value as ShipUnit
		ship.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	_check(
		not is_equal_approx(
			float(hunter.targeting.get(&"_evaluation_elapsed_sec")),
			float(same_team.targeting.get(&"_evaluation_elapsed_sec"))
		),
		"initial target evaluation schedules are staggered"
	)
	hunter.targeting.request_immediate_evaluation()
	await physics_frame
	_check(hunter.get_ai_target() == first_enemy, "nearest hostile target is selected")

	var pursuit_updates_before := hunter.ai.pursuit_navigation_update_count
	var path_calculations_before := hunter.navigation.path_calculation_count
	for _frame in 90:
		first_enemy.global_position.z += 0.75
		await physics_frame
	var pursuit_updates := hunter.ai.pursuit_navigation_update_count - pursuit_updates_before
	var path_calculations := hunter.navigation.path_calculation_count - path_calculations_before
	_observed_pursuit_updates = pursuit_updates
	_observed_path_calculations = path_calculations
	_check(pursuit_updates <= 3, "moving-target pursuit command is not refreshed every physics frame")
	_check(path_calculations <= 4, "navigation path calculation remains rate-limited")

	var update_count_before_threshold := hunter.ai.pursuit_navigation_update_count
	first_enemy.global_position.z += 300.0
	await physics_frame
	_check(
		hunter.ai.pursuit_navigation_update_count == update_count_before_threshold + 1,
		"target movement beyond 250 m refreshes pursuit immediately"
	)

	first_enemy.queue_free()
	await process_frame
	for _frame in 75:
		await physics_frame
	_check(hunter.get_ai_target() == fallback_enemy, "destroyed target is replaced within the evaluation interval")

	fallback_enemy.queue_free()
	await process_frame
	for _frame in 75:
		await physics_frame
	_check(hunter.get_ai_target() == null, "AI idles safely when no hostile candidate remains")
	_check(hunter.ai.behavior_state == ShipAI.BehaviorState.IDLE, "no-target behavior state is IDLE")

	var spawned_enemy := _spawn_ship("bb_ironwake", &"enemy", Vector3(7000.0, 0.0, -1000.0))
	_provider_units.append(spawned_enemy)
	spawned_enemy.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	for _frame in 75:
		await physics_frame
	_check(hunter.get_ai_target() == spawned_enemy, "AI acquires a hostile ship spawned after idle")
	_arena.queue_free()
	await process_frame
	await physics_frame
	_provider_units.clear()


func _test_class_ranges_and_carrier_behavior() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var destroyer := _spawn_ship("dd_bluewind", &"ally", Vector3(-2000.0, 0.0, 0.0))
	var cruiser := _spawn_ship("cl_tidebreaker", &"ally", Vector3(-1000.0, 0.0, 0.0))
	var battleship := _spawn_ship("bb_ironwake", &"ally", Vector3.ZERO)
	var carrier := _spawn_ship("cv_seabastion", &"ally", Vector3(1000.0, 0.0, 0.0))
	var enemy := _spawn_ship("dd_bluewind", &"enemy", Vector3(6000.0, 0.0, 0.0))
	_provider_units = [destroyer, cruiser, battleship, carrier, enemy]
	for ship_value in _provider_units:
		var ship := ship_value as ShipUnit
		ship.configure_ai_target_provider(Callable(self, &"_get_provider_units"))

	_check(
		is_equal_approx(
			destroyer.ai.get_effective_engagement_range_m(destroyer.combat, destroyer.ship_data),
			6825.0
		),
		"destroyer uses 65% of its 10.5 km primary range"
	)
	_check(
		is_equal_approx(
			cruiser.ai.get_effective_engagement_range_m(cruiser.combat, cruiser.ship_data),
			10500.0
		),
		"cruiser uses 75% of its 14 km primary range"
	)
	_check(
		is_equal_approx(
			battleship.ai.get_effective_engagement_range_m(battleship.combat, battleship.ship_data),
			17000.0
		),
		"battleship uses 85% of its 20 km primary range"
	)
	_check(
		carrier.ship_data.default_weapon_id == "carrier_secondary"
			and is_equal_approx(carrier.combat.get_primary_weapon_range_m(), 8000.0),
		"carrier uses its dedicated low-threat secondary weapon"
	)
	_check(
		is_equal_approx(destroyer.ai.get_minimum_separation_m(destroyer.ship_data, enemy), 380.0)
			and is_equal_approx(
				battleship.ai.get_minimum_separation_m(battleship.ship_data, enemy),
				745.0
			),
		"minimum separation combines both safety radii and class clearance"
	)

	carrier.targeting.request_immediate_evaluation()
	await physics_frame
	await physics_frame
	_check(carrier.ai.behavior_state == ShipAI.BehaviorState.RETREAT, "carrier separates before minimum collision range")
	_check(
		carrier.navigation.has_navigation_target
			and carrier.ai.carrier_separation_update_count == 1,
		"carrier creates one rate-limited early separation route"
	)

	_arena.queue_free()
	await process_frame
	await physics_frame
	_provider_units.clear()


func _spawn_ship(ship_id: String, team: StringName, position: Vector3) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	var source_data := _ship_database.get_ship(ship_id)
	ship.setup(source_data.duplicate(true) as ShipData, team, false, Color.WHITE)
	_arena.add_child(ship)
	ship.global_position = position
	return ship


func _get_provider_units() -> Array:
	var valid_units: Array = []
	for ship in _provider_units:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			valid_units.append(ship)
	return valid_units


func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(description)
