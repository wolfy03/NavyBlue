extends SceneTree

# Integration test for the air-dropped-torpedo arming fix.
#
# The bug this guards against: an air-dropped torpedo resets its travelled
# distance at WATER ENTRY (TorpedoProjectile._enter_water), so its arming
# distance is measured from the splash point, not from the aircraft release
# point. The AI safe-run distance therefore has to place the ship far enough
# BEYOND the water-entry point for the torpedo to arm before it reaches the hull.
#
# This test drives the real projectile mechanics end to end:
#   1. a real air drop -> ballistic-to-water transition resets arming at the
#      splash point (travelled distance 0, launch position = entry point);
#   2. a ship whose hull sits closer than the arming distance from that entry
#      point is NOT hit (arming safety holds);
#   3. a ship beyond the arming distance from the entry point IS hit and applies
#      damage.
# Steps 2/3 use the same proven _try_process_ship_proximity path as
# TorpedoXZCollisionTest, but with the launch position established by an actual
# water entry rather than a surface launch.

const EPSILON := 0.05

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_check(packed != null, "battle scene loads")
	if packed == null:
		_report()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED

	var enemies := scene.get("enemies") as Array
	var player := scene.get("player_ship") as ShipUnit
	_check(
		player != null and enemies != null and enemies.size() >= 1,
		"battle fixtures spawn"
	)
	if player == null or enemies == null or enemies.is_empty():
		scene.queue_free()
		await process_frame
		_report()
		return
	var target := enemies[0] as ShipUnit
	_park_all_ships_far_away()

	var half_length := target.ship_data.hull_size.z * 0.5 + 0.75
	var arming := 50.0

	# --- Part 1: arming resets at the water-entry point ---------------------
	var torpedo := _air_drop_into_water(scene, player, arming)
	_check(
		torpedo.launch_phase == TorpedoProjectile.LaunchPhase.ARMING,
		"air-dropped torpedo enters the arming phase at water entry"
	)
	_check(
		is_equal_approx(torpedo.travelled_distance_m, 0.0),
		"travelled distance resets to zero at water entry"
	)
	_check(
		not torpedo.armed,
		"torpedo is not armed at the moment of water entry"
	)
	var entry_z := torpedo.launch_position.z
	_check(
		absf(torpedo.global_position.z - entry_z) < EPSILON,
		"arming is measured from the splash point, not the release point"
	)

	# --- Part 2: hull inside the arming distance is not hit -----------------
	# Near hull face 25 m ahead of the entry point (< 50 m arming distance).
	_place_target_ahead(target, entry_z, 25.0 + half_length)
	var pre_arm_hit: bool = torpedo.call(
		&"_try_process_ship_proximity",
		Vector3(0.0, -800.0, entry_z + 20.0),
		Vector3(0.0, 800.0, entry_z + 30.0)
	)
	_check(
		not pre_arm_hit,
		"a hull inside the arming distance from water entry is not hit"
	)
	_check(
		not torpedo.impact_processed,
		"no damage is resolved before the torpedo has armed"
	)

	# --- Part 3: hull beyond the arming distance is hit ---------------------
	var armed_torpedo := _air_drop_into_water(scene, player, arming)
	var armed_entry_z := armed_torpedo.launch_position.z
	# Near hull face 80 m ahead of the entry point (> 50 m arming distance).
	var near_face_z := armed_entry_z + 80.0
	_place_target_ahead(target, armed_entry_z, 80.0 + half_length)
	var results: Array[DamageResult] = []
	armed_torpedo.hit_resolved.connect(
		func(result: DamageResult) -> void:
			results.append(result)
	)
	var armed_hit: bool = armed_torpedo.call(
		&"_try_process_ship_proximity",
		Vector3(0.0, 900.0, near_face_z - 5.0),
		Vector3(0.0, -900.0, near_face_z + 5.0)
	)
	_check(
		armed_hit,
		"a hull beyond the arming distance from water entry is hit"
	)
	_check(
		armed_torpedo.impact_processed,
		"the armed contact resolves an impact"
	)
	_check(
		not results.is_empty(),
		"the armed contact emits a DamageResult"
	)
	if not results.is_empty():
		_check(
			results[0].target_ship == target,
			"the resolved hit targets the intended ship"
		)

	scene.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null and object_pool.has_method(&"clear_pool"):
		object_pool.call(&"clear_pool")
	await process_frame
	_report()


func _air_drop_into_water(
		scene: Node,
		source_ship: ShipUnit,
		arming_distance_m: float
) -> TorpedoProjectile:
	var projectile_scene := load(
		"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
	) as PackedScene
	var torpedo := projectile_scene.instantiate() as TorpedoProjectile
	scene.get_node("Projectiles").add_child(torpedo)
	var data := load(
		"res://resources/projectiles/destroyer_torpedo.tres"
	).duplicate(true) as TorpedoProjectileData
	data.arming_distance_m = arming_distance_m
	data.direct_damage = 1.0
	data.explosion_damage = 0.0
	data.flooding_chance = 0.0
	var context := ProjectileLaunchContext.new()
	context.source_team = FactionRelations.PLAYER
	context.source_weapon_id = &"air_arming_test"
	context.initial_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 50.0, 0.0)
	)
	context.initial_velocity = Vector3(0.0, -5.0, 65.0)
	context.torpedo_launch_mode = TorpedoLaunchMode.Type.AIR_DROPPED
	context.intended_launch_direction = Vector3(0.0, 0.0, 1.0)
	torpedo.configure(data, BattleTestServices.create(self))
	torpedo.launch(context)
	# Teleport to just below the water surface at z = 0 and let the real update
	# perform the water entry (which resets arming at the splash point).
	torpedo.global_position = Vector3(0.0, torpedo.water_height_m - 0.1, 0.0)
	torpedo.call(&"_physics_process", 0.1)
	return torpedo


func _place_target_ahead(
		target: ShipUnit,
		entry_z: float,
		center_offset_z: float
) -> void:
	target.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 0.0, entry_z + center_offset_z)
	)


func _park_all_ships_far_away() -> void:
	var index := 0
	for value in get_nodes_in_group(&"ships"):
		var ship := value as ShipUnit
		if ship == null:
			continue
		ship.global_transform = Transform3D(
			Basis.IDENTITY,
			Vector3(6000.0 + float(index) * 500.0, 0.0, 6000.0)
		)
		index += 1


func _report() -> void:
	for failure in _failures:
		push_error("AIR TORPEDO ARMING: %s" % failure)
	print(
		"AIR_DROPPED_TORPEDO_ARMED_BEFORE_COLLISION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
