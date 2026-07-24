extends SceneTree

const EPSILON := 0.05

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_geometry_is_xz_only()
	await _test_torpedo_intersections()
	for failure in _failures:
		push_error("TORPEDO XZ COLLISION TEST: %s" % failure)
	if _failures.is_empty():
		print("TORPEDO_XZ_COLLISION_TEST PASS")
	quit(0 if _failures.is_empty() else 1)


func _test_geometry_is_xz_only() -> void:
	var result := CombatGeometryXZ.segment_rectangle_intersection_xz(
		Vector3(0.0, -500.0, 0.0),
		Vector3(0.0, 700.0, 200.0),
		Transform3D(Basis.IDENTITY, Vector3(0.0, 300.0, 100.0)),
		Vector2(5.0, 10.0)
	)
	_check(result.hit, "different Y ranges still intersect in XZ")
	_check_approx(result.ratio, 0.45, "slab result reports first entry ratio")
	_check_approx(result.position.z, 90.0, "entry position uses segment ratio")
	_check_approx(
		CombatGeometryXZ.distance_xz(
			Vector3(0.0, -1000.0, 0.0),
			Vector3(3.0, 1000.0, 4.0)
		),
		5.0,
		"horizontal distance excludes Y"
	)


func _test_torpedo_intersections() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_check(packed != null, "battle scene loads")
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED

	var player := scene.get("player_ship") as ShipUnit
	var enemies := scene.get("enemies") as Array
	_check(player != null and enemies.size() >= 2, "collision fixtures spawn")
	if player == null or enemies.size() < 2:
		scene.queue_free()
		await process_frame
		return
	var first_target := enemies[0] as ShipUnit
	var second_target := enemies[1] as ShipUnit
	_move_ships_out_of_test_lane()
	player.global_position = Vector3(-5000.0, 0.0, -5000.0)

	var data := load(
		"res://resources/projectiles/destroyer_torpedo.tres"
	).duplicate(true) as TorpedoProjectileData
	data.arming_distance_m = 50.0
	data.direct_damage = 1.0
	data.explosion_damage = 0.0
	data.flooding_chance = 0.0

	var boundary_torpedo := _spawn_torpedo(scene, data, player)
	var first_half_length := first_target.ship_data.hull_size.z * 0.5 + 0.75
	first_target.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 300.0, 49.0 + first_half_length)
	)
	var pre_arm_hit: bool = boundary_torpedo.call(
		&"_try_process_ship_proximity",
		Vector3(0.0, -800.0, 48.0),
		Vector3(0.0, 800.0, 53.0)
	)
	_check(not pre_arm_hit, "intersection before arming distance is ignored")
	_check(
		not boundary_torpedo.impact_processed,
		"pre-arm boundary crossing does not resolve damage"
	)

	first_target.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, -300.0, 50.5 + first_half_length)
	)
	var resolved_results: Array[DamageResult] = []
	boundary_torpedo.hit_resolved.connect(
		func(result: DamageResult) -> void:
			resolved_results.append(result)
	)
	var post_arm_hit: bool = boundary_torpedo.call(
		&"_try_process_ship_proximity",
		Vector3(0.0, 900.0, 48.0),
		Vector3(0.0, -900.0, 54.0)
	)
	_check(post_arm_hit, "intersection after arming distance resolves")
	_check(
		not resolved_results.is_empty(),
		"resolved hit emits a DamageResult"
	)
	if not resolved_results.is_empty():
		var boundary_result := resolved_results[0]
		_check_approx(
			boundary_result.hit_info.hit_position.z,
			50.5,
			"DamageResult records the actual XZ entry position"
		)
		_check(
			boundary_result.hit_info.armor_part == ArmorPart.Type.BOW,
			"underwater section uses the actual entry position"
		)

	var nearest_torpedo := _spawn_torpedo(scene, data, player)
	nearest_torpedo.torpedo_data.arming_distance_m = 0.0
	first_half_length = first_target.ship_data.hull_size.z * 0.5 + 0.75
	var second_half_length := second_target.ship_data.hull_size.z * 0.5 + 0.75
	first_target.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 0.0, 100.0 + first_half_length)
	)
	second_target.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 0.0, 150.0 + second_half_length)
	)
	var nearest_results: Array[DamageResult] = []
	nearest_torpedo.hit_resolved.connect(
		func(result: DamageResult) -> void:
			nearest_results.append(result)
	)
	var nearest_hit: bool = nearest_torpedo.call(
		&"_try_process_ship_proximity",
		Vector3(0.0, -100.0, 0.0),
		Vector3(0.0, 100.0, 300.0)
	)
	_check(nearest_hit, "swept segment hits at least one target")
	if not nearest_results.is_empty():
		_check(
			nearest_results[0].target_ship == first_target,
			"smallest intersection ratio wins regardless of group order"
		)
		_check_approx(
			nearest_results[0].hit_info.hit_position.z,
			100.0,
			"nearest target uses its first entry position"
		)

	var body_torpedo := _spawn_torpedo(scene, data, player)
	first_target.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 0.0, 49.0 + first_half_length)
	)
	body_torpedo.previous_position = Vector3(0.0, -400.0, 48.0)
	body_torpedo.global_position = Vector3(0.0, 400.0, 53.0)
	body_torpedo.call(&"_on_body_entered", first_target)
	_check(
		not body_torpedo.impact_processed,
		"body_entered also rejects a pre-arm contact position"
	)
	first_target.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 0.0, 51.0 + first_half_length)
	)
	body_torpedo.previous_position = Vector3(0.0, -400.0, 48.0)
	body_torpedo.global_position = Vector3(0.0, 400.0, 54.0)
	body_torpedo.call(&"_on_body_entered", first_target)
	_check(
		body_torpedo.impact_processed,
		"body_entered resolves an armed contact from the same XZ segment logic"
	)

	scene.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.clear_pool()


func _spawn_torpedo(
		scene: Node,
		data: TorpedoProjectileData,
		source_ship: ShipUnit
) -> TorpedoProjectile:
	var projectile_scene := load(
		"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
	) as PackedScene
	var torpedo := projectile_scene.instantiate() as TorpedoProjectile
	scene.get_node("Projectiles").add_child(torpedo)
	torpedo.setup_projectile_data(data.duplicate(true) as TorpedoProjectileData)
	var context := ProjectileLaunchContext.new()
	context.source_ship = source_ship
	context.source_team = source_ship.team
	context.source_weapon_id = &"xz_collision_test"
	context.initial_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	torpedo.launch_with_context(context)
	return torpedo


func _move_ships_out_of_test_lane() -> void:
	var index := 0
	for value in get_nodes_in_group(&"ships"):
		var ship := value as ShipUnit
		if ship == null:
			continue
		ship.global_transform = Transform3D(
			Basis.IDENTITY,
			Vector3(5000.0 + float(index) * 500.0, 0.0, 5000.0)
		)
		index += 1


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _check_approx(actual: float, expected: float, description: String) -> void:
	if absf(actual - expected) > EPSILON:
		_failures.append(
			"%s (expected %.3f, got %.3f)" % [
				description,
				expected,
				actual,
			]
		)
