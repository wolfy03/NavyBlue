extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/fighter_combat_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	var player := FighterTestSupport.find_carrier(
		battle,
		FactionRelations.PLAYER
	)
	var enemy := FighterTestSupport.find_carrier(
		battle,
		FactionRelations.ENEMY
	)
	FighterTestSupport.stop_carrier_ai(enemy)
	_check(player != null and enemy != null, "test carriers exist")
	if player == null or enemy == null:
		await _finish(battle)
		return
	var player_fighter := player.carrier_air_group.launch_squadron(
		"basic_fighter_squadron",
		Vector3.ZERO
	)
	var enemy_bomber := enemy.carrier_air_group.launch_squadron(
		"basic_bomber_squadron",
		Vector3.ZERO
	)
	var coordinator := battle.get_node_or_null(
		"Aircraft/AircraftCombatCoordinator"
	) as AircraftCombatCoordinator
	_check(
		coordinator != null \
			and player_fighter != null \
			and enemy_bomber != null,
		"squadrons register with battle coordinator"
	)
	if coordinator != null and player_fighter != null \
			and enemy_bomber != null:
		var hostile := coordinator.get_hostile_squadrons(
			FactionRelations.PLAYER
		)
		_check(
			hostile.has(enemy_bomber) \
				and not hostile.has(player_fighter),
			"coordinator excludes friendly squadrons"
		)
		var selected := coordinator.find_best_intercept_target(
			player_fighter,
			player.global_position,
			8000.0
		)
		_check(selected == enemy_bomber, "coordinator selects hostile bomber")
		coordinator.register_intercept_assignment(
			player_fighter,
			enemy_bomber
		)
		_check(
			coordinator.get_interceptor_count_for(enemy_bomber) == 1,
			"intercept assignment count is tracked"
		)
		coordinator.unregister_squadron(player_fighter)
		_check(
			coordinator.get_interceptor_count_for(enemy_bomber) == 0,
			"unregister clears assignment"
		)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("AIRCRAFT COMBAT COORDINATOR TEST: %s" % failure)
	print(
		"AIRCRAFT_COMBAT_COORDINATOR_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
