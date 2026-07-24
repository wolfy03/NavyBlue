extends SceneTree

const EPSILON := 0.05

var _failures: Array[String] = []


class DamageTarget:
	extends StaticBody3D

	var health: ShipHealth

	func configure() -> void:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 1.0, 4.0)
		shape.shape = box
		add_child(shape)
		var defense := ShipDefenseStats.new()
		defense.max_hp = 100.0
		defense.current_hp = 100.0
		defense.belt_armor = 50.0
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
		return health.apply_damage(damage, penetration_result, hit_info)

	func apply_damage_result(result: DamageResult) -> float:
		return health.apply_damage_result(result)


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_ballistic_ranges()
	await _test_direct_water_impact_and_pool()
	await _test_first_collision_selection()
	await _test_ricochet_visual_flow()
	for failure in _failures:
		push_error("SHELL BALLISTICS TEST: %s" % failure)
	if _failures.is_empty():
		print("SHELL_BALLISTICS_TEST PASS")
	quit(0 if _failures.is_empty() else 1)


func _test_ballistic_ranges() -> void:
	var weapon := WeaponDatabase.new().get_weapon("destroyer_cannon")
	var shell_data := weapon.projectile_data as ShellProjectileData \
		if weapon != null else null
	_check(weapon != null and shell_data != null, "ballistic resources load")
	if weapon == null or shell_data == null:
		return
	var gravity := BallisticMath.get_effective_gravity_mps2(shell_data)
	var results := ShellRangeTestRunner.evaluate_ranges(
		weapon.muzzle_velocity,
		gravity,
		weapon.range_meters
	)
	for result in results:
		var requested := float(result["distance_m"])
		var status := result["status"] as StringName
		if requested > weapon.range_meters:
			_check(status == &"OUT_OF_RANGE", "configured range + 100 is rejected")
			continue
		_check(bool(result["has_solution"]), "%.0f m has a ballistic solution" % requested)
		var allowed_ratio := 0.02 \
			if requested >= weapon.range_meters * 0.9 else 0.01
		_check(
			float(result["error_m"]) <= requested * allowed_ratio,
			"%.0f m ballistic error stays within %.0f%%" % [
				requested,
				allowed_ratio * 100.0,
			]
		)
		print(
			(
				"[ShellRangeTest] target=%.1f angle=%.2f actual=%.1f "
				+ "error=%.2f flight=%.2f status=%s"
			) % [
				requested,
				float(result["angle_degrees"]),
				float(result["actual_distance_m"]),
				float(result["error_m"]),
				float(result["flight_time_seconds"]),
				status,
			]
		)
	var physical_maximum := BallisticMath.calculate_maximum_range(
		weapon.muzzle_velocity,
		gravity,
		weapon.max_pitch_degrees
	)
	_check(
		physical_maximum >= weapon.range_meters,
		"physical maximum reaches the configured cannon range"
	)
	_check(
		weapon.range_meters > physical_maximum * 0.98,
		"configured range warning identifies the two-percent safety margin"
	)


func _test_direct_water_impact_and_pool() -> void:
	var projectile_scene := load(
		"res://scenes/weapon/projectiles/shell_projectile.tscn"
	) as PackedScene
	var shell_data := load(
		"res://resources/projectiles/small_ap_shell.tres"
	) as ShellProjectileData
	var parent := Node3D.new()
	root.add_child(parent)
	var pool := root.get_node_or_null("ObjectPool")
	var shell := pool.spawn(projectile_scene, parent) as ShellProjectile
	_check(shell != null, "ObjectPool spawns a direct-simulation shell")
	if shell == null:
		parent.queue_free()
		return
	shell.setup_projectile_data(shell_data)
	var gravity := shell.get_effective_gravity_mps2()
	var distance := 3000.0
	var angle_value: Variant = BallisticMath.solve_low_arc_angle(
		distance,
		-20.0,
		shell_data.muzzle_velocity,
		gravity
	)
	var angle := float(angle_value)
	var context := ProjectileLaunchContext.new()
	context.initial_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 20.0, 0.0)
	)
	context.initial_velocity = Vector3(
		0.0,
		shell_data.muzzle_velocity * sin(angle),
		-shell_data.muzzle_velocity * cos(angle)
	)
	context.aim_point = Vector3(0.0, 0.0, -distance)
	var water_events := [0]
	var on_water := func(_position: Vector3, _strength: float) -> void:
		water_events[0] += 1
	var event_bus := root.get_node_or_null("EventBus")
	event_bus.projectile_water_impact.connect(on_water)
	shell.launch_with_context(context)
	for _step in 10000:
		if not shell.active:
			break
		shell.call(&"_physics_process", 0.02)
	_check(
		shell.last_despawn_reason == Projectile.DespawnReason.WATER_IMPACT,
		"direct shell despawns from swept water intersection"
	)
	_check(
		absf(CombatGeometryXZ.distance_xz(
			shell.launch_position,
			shell.last_despawn_position
		) - distance) <= distance * 0.01,
		"direct shell lands within one percent at 3 km"
	)
	_check(water_events[0] == 1, "normal shell emits exactly one water impact")
	var reused := pool.spawn(projectile_scene, parent) as ShellProjectile
	_check(reused == shell, "ObjectPool reuses the direct shell")
	if reused != null:
		_check(
			not reused.active
				and reused.velocity.is_zero_approx()
				and reused.despawn_reason == Projectile.DespawnReason.NONE,
			"reused shell starts without stale flight state"
		)
		reused.despawn()
	if event_bus.projectile_water_impact.is_connected(on_water):
		event_bus.projectile_water_impact.disconnect(on_water)
	parent.queue_free()
	await process_frame


func _test_first_collision_selection() -> void:
	var target := DamageTarget.new()
	root.add_child(target)
	target.configure()
	var shell := Projectile.new()
	root.add_child(shell)
	await physics_frame
	target.global_position = Vector3(0.0, -2.0, 0.0)
	await physics_frame
	var water_first: ShellCollisionResult = shell.call(
		&"_find_first_collision",
		Vector3(0.0, 2.0, -10.0),
		Vector3(0.0, -6.0, 10.0)
	)
	_check(
		water_first.hit
			and water_first.type == ShellCollisionResult.Type.WATER,
		"water collision wins when it precedes a submerged hull"
	)
	target.global_position = Vector3(0.0, 1.4, 0.0)
	await physics_frame
	var ship_first: ShellCollisionResult = shell.call(
		&"_find_first_collision",
		Vector3(0.0, 3.0, -10.0),
		Vector3(0.0, -1.0, 10.0)
	)
	_check(
		ship_first.hit
			and ship_first.type == ShellCollisionResult.Type.SHIP
			and ship_first.target_ship == target,
		"ship collision wins when its ray ratio precedes the water"
	)
	shell.queue_free()
	target.queue_free()
	await process_frame


func _test_ricochet_visual_flow() -> void:
	var target := DamageTarget.new()
	root.add_child(target)
	target.configure()
	target.global_position = Vector3(0.0, 1.0, 0.0)
	var parent := Node3D.new()
	root.add_child(parent)
	var projectile_scene := load(
		"res://scenes/weapon/projectiles/shell_projectile.tscn"
	) as PackedScene
	var pool := root.get_node_or_null("ObjectPool")
	var shell := pool.spawn(projectile_scene, parent) as ShellProjectile
	await physics_frame
	shell.global_position = Vector3(-1.5, 1.0, -10.0)
	shell.gravity_scale = 0.0
	var ricochet_results: Array[DamageResult] = []
	var on_resolved := func(result: DamageResult) -> void:
		ricochet_results.append(result)
	shell.ship_hit_resolved.connect(on_resolved)
	var hp_before := target.get_defense_stats().current_hp
	var direction := Vector3(0.5, 0.0, 8.0).normalized()
	shell.launch(direction * 120.0, &"test")
	for _frame in 20:
		await physics_frame
		if not ricochet_results.is_empty():
			break
	_check(
		not ricochet_results.is_empty()
			and ricochet_results[0].hit_outcome == HitOutcome.Type.RICOCHET,
		"shallow swept hit resolves as RICOCHET"
	)
	_check(
		is_equal_approx(target.get_defense_stats().current_hp, hp_before),
		"AP ricochet applies no ship damage"
	)
	var ricochet := _find_ricochet(parent)
	_check(ricochet != null and ricochet.active, "ricochet visual is spawned")
	var water_events := [0]
	var water_strengths: Array[float] = []
	var on_water := func(_position: Vector3, strength: float) -> void:
		water_events[0] += 1
		water_strengths.append(strength)
	var event_bus := root.get_node_or_null("EventBus")
	event_bus.projectile_water_impact.connect(on_water)
	for _frame in 240:
		if ricochet == null or not ricochet.active:
			break
		await physics_frame
	_check(water_events[0] == 1, "ricochet emits one reduced water impact")
	_check(
		not water_strengths.is_empty() and water_strengths[0] < 1.0,
		"ricochet water impact is weaker than the base shell splash"
	)
	_check(
		is_equal_approx(target.get_defense_stats().current_hp, hp_before),
		"ricochet visual performs no secondary ship damage"
	)
	var ricochet_scene := load(
		"res://scenes/weapon/projectiles/ricochet_projectile_visual.tscn"
	) as PackedScene
	var reused_ricochet := pool.spawn(
		ricochet_scene,
		parent
	) as RicochetProjectileVisual
	_check(
		reused_ricochet == ricochet
			and not reused_ricochet.active
			and reused_ricochet.velocity.is_zero_approx(),
		"ObjectPool reuses a clean ricochet visual"
	)
	if reused_ricochet != null:
		reused_ricochet.despawn()
	if event_bus.projectile_water_impact.is_connected(on_water):
		event_bus.projectile_water_impact.disconnect(on_water)
	parent.queue_free()
	target.queue_free()
	await process_frame
	pool.clear_pool()


func _find_ricochet(parent: Node) -> RicochetProjectileVisual:
	if parent == null:
		return null
	for child in parent.get_children():
		if child is RicochetProjectileVisual:
			return child as RicochetProjectileVisual
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
