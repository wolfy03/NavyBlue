extends SceneTree

const BATTLE_LOOP_STAGE: StageData = preload(
	"res://resources/stages/tests/battle_loop_test.tres"
)

var _failures: Array[String] = []
var _had_run_save := false
var _saved_run: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_snapshot_run_save()
	await _test_freed_enemy_reference_safety()
	await _test_freed_death_connection_safety()
	await _test_battle_clear_and_reward_selection()
	await _test_battle_failure()
	_restore_run_save()
	for failure in _failures:
		push_error("BATTLE LOOP TEST: %s" % failure)
	quit(0 if _failures.is_empty() else 1)

func _test_freed_enemy_reference_safety() -> void:
	var controller := BattleStateController.new()
	root.add_child(controller)
	var freed_enemy := ShipUnit.new()
	controller.enemies = [freed_enemy]
	freed_enemy.free()
	_check(
		controller._all_enemies_destroyed(),
		"freed enemy references count as destroyed"
	)
	_check(
		controller.enemies.is_empty(),
		"freed enemy references are pruned from battle state"
	)
	controller.free()
	await process_frame

func _test_freed_death_connection_safety() -> void:
	var controller := BattleStateController.new()
	root.add_child(controller)
	var freed_health := Node.new()
	root.add_child(freed_health)
	controller._death_connections = [{
		"health": freed_health,
		"callback": Callable(),
	}]
	freed_health.free()
	controller.stop_battle()
	_check(
		controller._death_connections.is_empty(),
		"freed health connections are safely cleared"
	)
	controller.free()
	await process_frame

func _test_battle_clear_and_reward_selection() -> void:
	var scene: Node = await _instantiate_battle_scene()
	if scene == null:
		return
	var enemies: Array = scene.get("enemies")
	for enemy in enemies:
		_apply_lethal_damage(enemy)
	for _frame in 8:
		await process_frame
		await physics_frame
	var game_manager = root.get_node_or_null("GameManager")
	var run_manager = root.get_node_or_null("RunManager")
	_check(game_manager != null and game_manager.get_mode_name() == "REWARD", "enemy wipe enters reward mode")
	_check(run_manager != null and run_manager.pending_rewards.size() == 3, "battle clear stores three pending rewards")
	if run_manager != null and not run_manager.pending_rewards.is_empty():
		var reward_id := str(run_manager.pending_rewards[0])
		var reward_system: Node = load("res://scripts/meta/RewardSystem.gd").new()
		root.add_child(reward_system)
		var selected: bool = reward_system.select_reward(reward_id)
		_check(selected, "reward selection returns true")
		_check(run_manager.active_upgrades.has(reward_id), "selected reward is added to active upgrades")
		_check(run_manager.pending_rewards.is_empty(), "reward selection clears pending rewards")
		reward_system.queue_free()
	scene.queue_free()
	await process_frame

func _test_battle_failure() -> void:
	var run_manager = root.get_node_or_null("RunManager")
	if run_manager != null:
		run_manager.start_new_run({
			"sea_id": "test_sea",
			"stage_id": "test_level",
			"stage_index": 0,
			"difficulty": 1.0,
		})
	var scene: Node = await _instantiate_battle_scene()
	if scene == null:
		return
	var enemies: Array = scene.get("enemies").duplicate()
	if not enemies.is_empty():
		_apply_lethal_damage(enemies[0])
		for _frame in 3:
			await process_frame
			await physics_frame
	_apply_lethal_damage(scene.get("player_ship"))
	for _frame in 8:
		await process_frame
		await physics_frame
	var game_manager = root.get_node_or_null("GameManager")
	run_manager = root.get_node_or_null("RunManager")
	_check(game_manager != null and game_manager.get_mode_name() == "GAME_OVER", "player death enters game over mode")
	_check(run_manager == null or not run_manager.is_run_active, "battle failure finishes the active run")
	scene.queue_free()
	await process_frame

func _instantiate_battle_scene() -> Node:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_check(packed != null, "battle scene packed resource loads")
	if packed == null:
		return null
	var scene := packed.instantiate() as BattleScene
	scene.stage_override = BATTLE_LOOP_STAGE
	root.add_child(scene)
	await process_frame
	await physics_frame
	_check(scene.get("player_ship") != null, "battle scene spawns player ship")
	var enemies: Array = scene.get("enemies")
	_check(enemies.size() == 3, "battle scene spawns test enemies")
	return scene

func _apply_lethal_damage(ship) -> void:
	if not is_instance_valid(ship):
		return
	var health: Node = ship.get_node_or_null("ShipHealth")
	if health != null and health.has_method("apply_damage"):
		health.apply_damage(999999.0)

func _snapshot_run_save() -> void:
	var save_manager = root.get_node_or_null("SaveManager")
	if save_manager == null:
		return
	_had_run_save = save_manager.run_exists()
	if _had_run_save:
		_saved_run = save_manager.load_run().duplicate(true)

func _restore_run_save() -> void:
	var save_manager = root.get_node_or_null("SaveManager")
	if save_manager != null:
		if _had_run_save:
			save_manager.save_run(_saved_run)
		else:
			save_manager.delete_run()
	var run_manager = root.get_node_or_null("RunManager")
	if run_manager != null:
		run_manager.reset_run()
	var game_manager = root.get_node_or_null("GameManager")
	if game_manager != null:
		game_manager.enter_main_menu()
	var object_pool = root.get_node_or_null("ObjectPool")
	if object_pool != null and object_pool.has_method("clear_pool"):
		object_pool.clear_pool()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
