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


class NullOceanManager:
	extends Node

	func get_surface_intersection_hit(
			_segment_start: Vector3,
			_segment_end: Vector3
	) -> Variant:
		return null

	func get_water_height(_position: Vector3) -> float:
		return 0.0


class InvalidOceanManager:
	extends Node

	func get_surface_intersection_hit(
			_segment_start: Vector3,
			_segment_end: Vector3
	) -> Variant:
		return "invalid"

	func get_water_height(_position: Vector3) -> float:
		return 0.0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_ballistic_ranges()
	_test_time_to_height()
	_test_ocean_manager_fallbacks()
	await _test_direct_water_impact_and_pool()
	await _test_first_collision_selection()
	await _test_collision_exclusion_and_obstacle_policy()
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
	var results := BallisticMathTestRunner.evaluate_ranges(
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
				"[BallisticMathTest] target=%.1f angle=%.2f actual=%.1f "
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


func _test_time_to_height() -> void:
	var time_value: Variant = BallisticMath.calculate_time_to_height(
		5.0,
		0.0,
		8.0,
		9.8
	)
	_check(time_value != null, "time-to-height finds the descending root")
	if time_value != null:
		var impact_height := BallisticMath.calculate_position(
			Vector3(0.0, 5.0, 0.0),
			Vector3(0.0, 8.0, 0.0),
			9.8,
			float(time_value)
		).y
		_check(
			absf(impact_height) <= EPSILON,
			"time-to-height reaches the requested surface"
		)
	_check(
		BallisticMath.calculate_time_to_height(1.0, 0.0, 2.0, 0.0) == null,
		"time-to-height rejects non-positive gravity"
	)
	_check(
		is_zero_approx(float(BallisticMath.calculate_time_to_height(
			-0.1,
			0.0,
			2.0,
			9.8
		))),
		"time-to-height returns zero below the target surface"
	)


func _test_ocean_manager_fallbacks() -> void:
	var null_manager := NullOceanManager.new()
	var null_hit := WaterIntersection.find_surface_intersection(
		null,
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, -1.0, 1.0),
		0.0,
		null_manager
	)
	_check(
		null_hit != null and null_hit.hit,
		"null OceanManager results fall back to the water plane"
	)
	var invalid_manager := InvalidOceanManager.new()
	var invalid_hit := WaterIntersection.find_surface_intersection(
		null,
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, -1.0, 1.0),
		0.0,
		invalid_manager,
		false
	)
	_check(
		invalid_hit != null and invalid_hit.hit,
		"invalid OceanManager result types fall back safely"
	)
	null_manager.free()
	invalid_manager.free()


func _test_direct_water_impact_and_pool() -> void:
	var projectile_scene := load(
		"res://scenes/weapon/projectiles/shell_projectile.tscn"
	) as PackedScene
	var shell_data := load(
		"res://resources/projectiles/small_ap_shell.tres"
	) as ShellProjectileData
	var parent := Node3D.new()
	root.add_child(parent)
	var ocean_manager := Node.new()
	ocean_manager.add_to_group(&"ocean_manager")
	root.add_child(ocean_manager)
	var pool := root.get_node_or_null("ObjectPool")
	var shell := pool.spawn(projectile_scene, parent) as ShellProjectile
	_check(shell != null, "ObjectPool spawns a direct-simulation shell")
	if shell == null:
		parent.queue_free()
		return
	shell.configure(shell_data, BattleTestServices.create(self))
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
	var launch_origin := context.initial_transform.origin
	shell.launch(context)
	_check(
		shell.call(&"_get_cached_ocean_manager") == ocean_manager,
		"shell caches the OceanManager once at launch"
	)
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
			launch_origin,
			shell.last_despawn_position
		) - distance) <= distance * 0.01,
		"direct shell lands within one percent at 3 km"
	)
	_check(
		water_events[0] == 1,
		"normal shell emits exactly one water impact (actual=%d)"
			% water_events[0]
	)
	_check(
		bool(shell.get(&"_despawn_requested")),
		"pooled shell stays despawn-locked while recycled"
	)
	var reused := pool.spawn(projectile_scene, parent) as ShellProjectile
	_check(reused == shell, "ObjectPool reuses the direct shell")
	if reused != null:
		_check(
			not reused.active
				and reused.velocity.is_zero_approx()
				and reused.despawn_reason == Projectile.DespawnReason.NONE
				and reused.projectile_data == null
				and reused.source_team == &"neutral"
				and reused.collision_excludes.is_empty()
				and reused.ocean_manager_ref == null
				and not bool(reused.get(&"_despawn_requested")),
			"reused shell starts without stale flight state"
		)
		reused.despawn()
	if event_bus.projectile_water_impact.is_connected(on_water):
		event_bus.projectile_water_impact.disconnect(on_water)
	parent.queue_free()
	ocean_manager.queue_free()
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


func _test_collision_exclusion_and_obstacle_policy() -> void:
	var source := DamageTarget.new()
	root.add_child(source)
	source.global_position = Vector3(0.0, 2.0, -8.0)
	source.configure()
	var source_sensor := Area3D.new()
	source_sensor.position = Vector3(0.0, 0.0, 3.0)
	source.add_child(source_sensor)
	_add_box_collision(source_sensor, Vector3(2.0, 2.0, 2.0))

	var ignored_sensor_parent := Node3D.new()
	ignored_sensor_parent.add_to_group(&"projectile_sensor")
	root.add_child(ignored_sensor_parent)
	ignored_sensor_parent.global_position = Vector3(0.0, 2.0, 0.0)
	var ignored_sensor := Area3D.new()
	ignored_sensor_parent.add_child(ignored_sensor)
	_add_box_collision(ignored_sensor, Vector3(2.0, 2.0, 1.0))

	var obstacle := StaticBody3D.new()
	root.add_child(obstacle)
	obstacle.global_position = Vector3(0.0, 2.0, 2.0)
	_add_box_collision(obstacle, Vector3(2.0, 2.0, 1.0))

	var target := DamageTarget.new()
	root.add_child(target)
	target.global_position = Vector3(0.0, 2.0, 7.0)
	target.configure()
	var water_area := Area3D.new()
	water_area.add_to_group(&"shell_ignored")
	root.add_child(water_area)

	var shell := Projectile.new()
	root.add_child(shell)
	await physics_frame
	shell.call(&"_apply_launch_source", source, &"test", &"test_cannon")
	shell.call(&"_cache_collision_excludes")
	_check(
		shell.collision_excludes.size() == 2,
		"source ship root and child collision RIDs are cached once"
	)
	var dynamic_source_area := Area3D.new()
	dynamic_source_area.position = Vector3(0.0, 0.0, 6.0)
	source.add_child(dynamic_source_area)
	_add_box_collision(dynamic_source_area, Vector3(2.0, 2.0, 1.0))
	await physics_frame
	_check(
		not shell.collision_excludes.has(dynamic_source_area.get_rid()),
		"dynamic source collider is absent from the launch cache"
	)
	var setup_issues := shell.debug_validate_collision_setup(
		source,
		ignored_sensor,
		ignored_sensor,
		obstacle,
		water_area
	)
	_check(
		setup_issues.is_empty(),
		"collision layers and parent-group sensors validate"
	)
	var obstacle_hit: ShellCollisionResult = shell.call(
		&"_query_ship_collision",
		Vector3(0.0, 2.0, -12.0),
		Vector3(0.0, 2.0, 12.0)
	)
	_check(
		obstacle_hit.hit
			and obstacle_hit.type == ShellCollisionResult.Type.WORLD_OBSTACLE
			and obstacle_hit.collider == obstacle,
		"dynamic source and parent-group sensors are skipped before obstacles"
	)

	var event_bus := root.get_node_or_null("EventBus")
	var water_events := [0]
	var on_water := func(_position: Vector3, _strength: float) -> void:
		water_events[0] += 1
	event_bus.projectile_water_impact.connect(on_water)
	var world_effect_count_before := get_nodes_in_group(
		&"world_impact_effect"
	).size()
	var obstacle_shell := Projectile.new()
	root.add_child(obstacle_shell)
	obstacle_shell.configure(
		load("res://resources/projectiles/small_ap_shell.tres"),
		BattleTestServices.create(self)
	)
	obstacle_shell.velocity = Vector3.FORWARD * 100.0
	obstacle_shell.call(&"_process_collision", obstacle_hit)
	_check(
		obstacle_shell.last_despawn_reason \
			== Projectile.DespawnReason.WORLD_OBSTACLE,
		"world obstacle uses the dedicated despawn reason"
	)
	_check(
		water_events[0] == 0,
		"world obstacle does not emit a water impact"
	)
	_check(
		get_nodes_in_group(&"world_impact_effect").size()
			== world_effect_count_before + 1,
		"WorldImpactService emits exactly one obstacle effect"
	)

	obstacle.queue_free()
	await physics_frame
	var ship_hit: ShellCollisionResult = shell.call(
		&"_query_ship_collision",
		Vector3(0.0, 2.0, -12.0),
		Vector3(0.0, 2.0, 12.0)
	)
	_check(
		ship_hit.hit
			and ship_hit.type == ShellCollisionResult.Type.SHIP
			and ship_hit.target_ship == target,
		"dynamic source collider is skipped before the enemy ship"
	)
	_check(
		is_equal_approx(
			source.get_defense_stats().current_hp,
			source.get_defense_stats().max_hp
		),
		"source ship receives no self-hit damage"
	)
	shell.shell_collision_mask = 0
	_check(
		not bool(shell.call(&"_validate_collision_mask", false)),
		"empty shell collision masks are detected"
	)
	shell.queue_free()
	source.queue_free()
	ignored_sensor_parent.queue_free()
	target.queue_free()
	water_area.queue_free()
	if event_bus.projectile_water_impact.is_connected(on_water):
		event_bus.projectile_water_impact.disconnect(on_water)
	for effect in get_nodes_in_group(&"world_impact_effect"):
		effect.queue_free()
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
	var ricochet_data := load(
		"res://resources/projectiles/small_ap_shell.tres"
	) as ShellProjectileData
	shell.configure(ricochet_data, BattleTestServices.create(self))
	var ricochet_context := ProjectileLaunchContext.new()
	ricochet_context.source_team = &"test"
	ricochet_context.initial_transform = shell.global_transform
	ricochet_context.initial_velocity = direction * 120.0
	shell.launch(ricochet_context)
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
	if ricochet != null:
		_check(
			ricochet.global_position.y > 0.0,
			"ricochet visual starts above the water surface"
		)
		_check(
			ricochet.velocity.y > 0.0,
			"ricochet visual keeps a minimum upward component"
		)
		_check(
			ricochet.active_lifetime_seconds > 0.5
				and ricochet.active_lifetime_seconds
					<= ricochet.emergency_maximum_lifetime_seconds,
			"ricochet lifetime is derived from its water arrival time"
		)
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
	if ricochet != null:
		_check(
			bool(ricochet.get(&"_despawn_requested")),
			"pooled ricochet stays despawn-locked while recycled"
		)
	var reused_ricochet := pool.spawn(
		ricochet_scene,
		parent
	) as RicochetProjectileVisual
	_check(
		reused_ricochet == ricochet
			and not reused_ricochet.active
			and reused_ricochet.velocity.is_zero_approx()
			and is_zero_approx(reused_ricochet.active_lifetime_seconds)
			and not reused_ricochet.get(&"_despawn_requested"),
		"ObjectPool reuses a clean ricochet visual"
	)
	if reused_ricochet != null:
		var high_ricochet_start := Vector3(0.0, 2.0, 0.0)
		reused_ricochet.direction_randomness = 0.0
		reused_ricochet.launch(
			high_ricochet_start,
			Vector3(20.0, -200.0, -20.0),
			Vector3.UP,
			0.0,
			1.0,
			null,
			BattleTestServices.create(self).projectile_pool,
			BattleTestServices.create(self).events
		)
		_check(
			reused_ricochet.global_position.distance_to(
				high_ricochet_start
			) > 0.0,
			"ricochet visual applies a surface and forward offset"
		)
		_check(
			reused_ricochet.active_lifetime_seconds > 12.0
				and reused_ricochet.active_lifetime_seconds
					<= reused_ricochet.emergency_maximum_lifetime_seconds,
			"long ricochet is not clipped by the former 12 second limit"
		)
		_check(
			reused_ricochet.velocity.y \
				<= reused_ricochet.maximum_upward_speed_mps,
			"ricochet upward speed respects its visual safety limit"
		)
		for _step in 2000:
			if not reused_ricochet.active:
				break
			reused_ricochet.call(&"_physics_process", 0.02)
		_check(
			not reused_ricochet.active and water_events[0] == 2,
			"high ricochet reaches water before lifetime expiry"
		)
		_check(
			bool(reused_ricochet.get(&"_despawn_requested")),
			"recycled high ricochet stays despawn-locked"
		)
		var second_reuse := pool.spawn(
			ricochet_scene,
			parent
		) as RicochetProjectileVisual
		_check(
			second_reuse == reused_ricochet
				and is_zero_approx(second_reuse.active_lifetime_seconds)
				and second_reuse.velocity.is_zero_approx()
				and not bool(second_reuse.get(&"_despawn_requested")),
			"recycled high ricochet clears lifetime and despawn state"
		)
		if second_reuse != null:
			second_reuse.direction_randomness = 0.0
			second_reuse.launch(
				Vector3(0.0, 2.0, 0.0),
				Vector3(0.0, -1000.0, 0.0),
				Vector3.UP,
				0.0,
				1.0,
				null,
				BattleTestServices.create(self).projectile_pool,
				BattleTestServices.create(self).events
			)
			_check(
				is_equal_approx(
					second_reuse.active_lifetime_seconds,
					second_reuse.emergency_maximum_lifetime_seconds
				),
				"extreme ricochet uses the emergency lifetime cap"
			)
			for _step in 2000:
				if not second_reuse.active:
					break
				second_reuse.call(&"_physics_process", 0.02)
			_check(
				not second_reuse.active and water_events[0] == 2,
				"emergency lifetime expiry does not fake a water impact"
			)
			var third_reuse := pool.spawn(
				ricochet_scene,
				parent
			) as RicochetProjectileVisual
			_check(
				third_reuse == second_reuse
					and not bool(third_reuse.get(&"_despawn_requested"))
					and is_zero_approx(
						third_reuse.active_lifetime_seconds
					),
				"emergency-expired ricochet respawns with clean state"
			)
			if third_reuse != null:
				third_reuse.despawn()
	if event_bus.projectile_water_impact.is_connected(on_water):
		event_bus.projectile_water_impact.disconnect(on_water)
	parent.queue_free()
	target.queue_free()
	await process_frame
	pool.clear_pool()


func _add_box_collision(parent: CollisionObject3D, size: Vector3) -> void:
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision_shape.shape = box
	parent.add_child(collision_shape)


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
