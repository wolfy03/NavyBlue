extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	if packed == null:
		push_error("battle_scene load failed")
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var ships_root := scene.get_node_or_null("Ships")
	var projectiles := scene.get_node_or_null("Projectiles")
	var controller := scene.get_node_or_null("BattleStateController")
	var spawn_system := scene.get_node_or_null("SpawnSystem")
	var player_ship = scene.get("player_ship")
	var allies: Array = scene.get("allies")
	var enemies: Array = scene.get("enemies")
	var reward_system = load("res://scripts/meta/RewardSystem.gd").new()
	var rewards: Array = reward_system.roll_upgrade_rewards(3, "test_rewards")
	var reward_resources_ok := rewards.all(func(reward): return reward is UpgradeData)
	var object_pool = load("res://scripts/core/ObjectPool.gd").new()
	root.add_child(object_pool)
	var projectile_scene := load("res://scenes/weapon/projectile.tscn") as PackedScene
	var pooled_projectile = object_pool.spawn(projectile_scene, projectiles)
	var pool_spawn_ok: bool = pooled_projectile != null and pooled_projectile.get_meta("pool_key", "") == projectile_scene.resource_path
	if pooled_projectile != null:
		object_pool.recycle(pooled_projectile)
	var ok: bool = ships_root != null \
		and projectiles != null \
		and controller != null \
		and spawn_system != null \
		and player_ship != null \
		and allies.size() == 2 \
		and enemies.size() == 3 \
		and rewards.size() == 3 \
		and reward_resources_ok \
		and pool_spawn_ok

	print(
		"SMOKE battle ok=%s ships=%d allies=%d enemies=%d controller_active=%s projectiles=%s rewards=%d pool=%s" % [
			ok,
			ships_root.get_child_count() if ships_root != null else -1,
			allies.size(),
			enemies.size(),
			controller.get("battle_active") if controller != null else false,
			projectiles != null,
			rewards.size(),
			pool_spawn_ok,
		]
	)
	object_pool.clear_pool()
	object_pool.queue_free()
	reward_system.free()
	scene.queue_free()
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if ok else 1)
