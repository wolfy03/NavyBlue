extends Node3D

class DamageTarget:
	extends StaticBody3D

	var health: ShipHealth
	var last_hit_info: HitInfo

	func configure() -> void:
		var collision_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(20.0, 20.0, 30.0)
		collision_shape.shape = box
		add_child(collision_shape)
		var defense := ShipDefenseStats.new()
		defense.max_hp = 1000.0
		defense.current_hp = 1000.0
		defense.belt_armor = 40.0
		health = ShipHealth.new()
		health.debug_damage_log = false
		add_child(health)
		health.setup(defense)

	func get_defense_stats() -> ShipDefenseStats:
		return health.get_defense_stats()

	func apply_damage(
			damage: float,
			penetration_result: int,
			hit_info: HitInfo
	) -> float:
		last_hit_info = hit_info
		return health.apply_damage(damage, penetration_result, hit_info)


var _failures: Array[String] = []
var _shell_hit_count := 0
var _last_result: DamageResult


func _ready() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var controller := get_node_or_null(
		"CombatEffectController"
	) as CombatEffectController
	_check(controller != null, "CombatEffectController exists")
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.shell_hit.connect(_on_shell_hit)

	var target := DamageTarget.new()
	target.name = "DamageTarget"
	add_child(target)
	target.global_position = Vector3(0.0, 20.0, 0.0)
	target.configure()

	var projectile_scene := load(
		"res://scenes/weapon/projectile.tscn"
	) as PackedScene
	var projectile := projectile_scene.instantiate() as Projectile
	_check(projectile != null, "actual shell projectile instantiates")
	if projectile == null:
		_finish()
		return
	$Projectiles.add_child(projectile)
	projectile.global_position = Vector3(-80.0, 20.0, 0.0)
	projectile.gravity_scale = 0.0
	projectile.water_height = -100.0
	var shell_data := load(
		"res://resources/projectiles/small_ap_shell.tres"
	).duplicate(true) as ShellProjectileData
	shell_data.penetration = 500.0
	var hp_before := target.get_defense_stats().current_hp
	var context := ProjectileLaunchContext.new()
	context.source_team = &"test"
	context.initial_transform = projectile.global_transform
	context.initial_velocity = Vector3.RIGHT * 320.0
	projectile.configure(
		shell_data,
		BattleTestServices.create(get_tree())
	)
	projectile.launch(context)

	for _frame in 60:
		await get_tree().physics_frame
		if _shell_hit_count > 0:
			break

	var state := controller.get_debug_state() if controller != null else {}
	_check(_shell_hit_count == 1, "shell_hit EventBus signal emits once")
	_check(_last_result != null and _last_result.resolved, "shell damage resolves")
	_check(
		int(state.get("active_shell_impacts", 0)) == 1,
		"actual shell hit activates one pooled ship impact effect"
	)
	_check(
		projectile.last_despawn_reason == Projectile.DespawnReason.SHIP_HIT,
		"actual shell despawns with SHIP_HIT"
	)
	var hp_after_hit := target.get_defense_stats().current_hp
	_check(hp_after_hit < hp_before, "actual shell applies damage once")

	var non_penetrated := DamageResult.new()
	non_penetrated.hit_outcome = HitOutcome.Type.NON_PENETRATED
	non_penetrated.damage_type = DamageType.Type.SHELL_AP
	non_penetrated.raw_damage = 10.0
	controller.spawn_shell_impact(
		Vector3(5.0, 20.0, 0.0),
		Vector3.LEFT,
		Vector3.RIGHT * 250.0,
		non_penetrated.hit_outcome,
		ShellStats.ShellType.AP,
		1.0
	)
	var ricochet := DamageResult.new()
	ricochet.hit_outcome = HitOutcome.Type.RICOCHET
	ricochet.damage_type = DamageType.Type.SHELL_AP
	ricochet.raw_damage = 1.0
	controller.spawn_shell_impact(
		Vector3(-5.0, 20.0, 0.0),
		Vector3.LEFT,
		Vector3.RIGHT * 250.0,
		ricochet.hit_outcome,
		ShellStats.ShellType.AP,
		0.75
	)
	state = controller.get_debug_state() if controller != null else {}
	_check(
		int(state.get("active_shell_impacts", 0)) == 3,
		"penetrated, non-penetrated, and ricochet visuals share the pool"
	)
	_check(
		is_equal_approx(
			target.get_defense_stats().current_hp,
			hp_after_hit
		),
		"visual-only service calls apply no additional damage"
	)
	var reusable_pool := controller._shell_pool \
		if controller != null else null
	if reusable_pool != null and not reusable_pool._effects.is_empty():
		var reusable_effect := \
			reusable_pool._effects[0] as PooledEffectBase
		if reusable_effect != null:
			reusable_effect.deactivate()
		var request := EffectRequest.new()
		request.position = Vector3(0.0, 20.0, 4.0)
		request.normal = Vector3.LEFT
		request.velocity = Vector3.RIGHT * 250.0
		request.hit_outcome = HitOutcome.Type.PENETRATED
		request.shell_type = ShellStats.ShellType.AP
		request.strength = 1.0
		var respawned := reusable_pool.spawn_effect(request)
		_check(
			respawned == reusable_effect,
			"inactive ship impact effect is reused from the pool"
		)
		var stale_effect := reusable_pool._effects.back() as Node
		stale_effect.free()
		reusable_pool.call(&"_build_pool")
		_check(
			reusable_pool.get_pool_size() == controller.shell_pool_size,
			"freed effect entries are pruned and replenished"
		)

	if event_bus != null and event_bus.shell_hit.is_connected(_on_shell_hit):
		event_bus.shell_hit.disconnect(_on_shell_hit)
	var object_pool := get_node_or_null("/root/ObjectPool")
	if object_pool != null:
		object_pool.clear_pool()
	if controller != null:
		controller.clear_pools()
	target.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_finish()


func _on_shell_hit(
	_projectile,
	_target_ship,
	_hit_position: Vector3,
	_hit_normal: Vector3,
	result
) -> void:
	_shell_hit_count += 1
	_last_result = result as DamageResult


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("SHELL SHIP IMPACT EFFECT TEST: %s" % failure)
	if _failures.is_empty():
		print("SHELL_SHIP_IMPACT_EFFECT_TEST PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
