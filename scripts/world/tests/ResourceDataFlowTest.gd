extends SceneTree

const BATTLE_LOOP_STAGE: StageData = preload(
	"res://resources/stages/tests/battle_loop_test.tres"
)

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_content_resources()
	await _test_runtime_flow()
	for failure in _failures:
		push_error("RESOURCE DATA FLOW: %s" % failure)
	quit(0 if _failures.is_empty() else 1)

func _test_content_resources() -> void:
	var ship_database := ShipDatabase.new()
	var stage_database := StageDatabase.new()
	ship_database.warn_on_fallback = false
	stage_database.warn_on_fallback = false
	var weapon_database := WeaponDatabase.new()
	_check(ship_database.get_ship("dd_bluewind") is ShipData, "ShipDatabase returns ShipData")
	_check(ship_database.get_ship("unknown_ship").id == "dd_bluewind", "ShipDatabase fallback is valid")
	var stage := stage_database.get_stage("battle_loop_test")
	_check(
		stage is StageData and stage.enemy_spawns.size() == 3,
		"StageDatabase loads the battle loop fixture"
	)
	_check(stage_database.get_stage("unknown_stage").id == "test_level", "StageDatabase fallback is valid")
	var weapon := weapon_database.get_weapon("battleship_cannon")
	_check(weapon is WeaponData, "WeaponDatabase returns WeaponData")
	_check(weapon.projectile_data is ProjectileData, "WeaponData references ProjectileData")
	for path in [
		"res://resources/projectiles/small_ap_shell.tres",
		"res://resources/projectiles/medium_ap_shell.tres",
		"res://resources/projectiles/he_shell.tres",
		"res://resources/projectiles/heavy_ap_shell.tres",
	]:
		_check(load(path) is ProjectileData, "%s loads as ProjectileData" % path)
	var reward_system := RewardSystem.new()
	var rewards := reward_system.roll_upgrade_rewards()
	_check(rewards.size() == 3, "RewardSystem rolls three resources")
	_check(rewards.all(func(reward): return reward is UpgradeData), "RewardSystem returns UpgradeData resources")
	_check(reward_system.get_reward_ids(rewards).size() == 3, "Rewards serialize to upgrade ids")
	reward_system.free()

func _test_runtime_flow() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_check(packed != null, "battle_scene.tscn loads")
	if packed == null:
		return
	var scene := packed.instantiate() as BattleScene
	scene.stage_override = BATTLE_LOOP_STAGE
	root.add_child(scene)
	await process_frame
	await physics_frame
	var player = scene.get("player_ship")
	_check(player != null, "StageData spawns the player")
	_check(
		scene.get("allies").size() == 1 \
			and scene.get("enemies").size() == 3,
		"StageData spawns both fleets"
	)
	var controller := scene.get_node_or_null("BattleStateController")
	_check(controller != null and controller.battle_active, "BattleStateController starts with the battle")
	if player != null:
		var cannons: Array[WeaponMount] = player.combat.get_weapons_by_type(
			WeaponTypes.Type.CANNON
		)
		_check(not cannons.is_empty(), "ShipVisualBuilder creates cannon mounts")
		if not cannons.is_empty():
			var turret := cannons[0] as CannonMount
			_check(turret.weapon_data is WeaponData, "Turret receives WeaponData")
			var aim_point: Vector3 = player.global_position \
				+ -player.global_transform.basis.z * 1000.0
			turret.aim_at(aim_point)
			turret.call(&"_turn_toward", aim_point, 10.0)
			var fired := turret.fire()
			_check(fired, "Turret fires")
			var projectiles := scene.get_node_or_null("Projectiles")
			var projectile: Projectile = projectiles.get_child(0) as Projectile if projectiles != null and projectiles.get_child_count() > 0 else null
			_check(projectile != null, "Turret creates a projectile")
			if projectile != null:
				_check(projectile.projectile_data is ProjectileData, "Projectile receives ProjectileData")
				_check(not str(projectile.get_meta("pool_key", "")).is_empty(), "Projectile is spawned through ObjectPool")
				projectile.despawn()
				var object_pool := root.get_node_or_null("ObjectPool")
				_check(
					object_pool != null
						and projectile.get_parent() == object_pool
						and bool(projectile.get_meta("in_object_pool", false)),
					"Projectile returns to ObjectPool"
				)
	scene.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.clear_pool()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
