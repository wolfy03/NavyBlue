extends SceneTree

const EPSILON := 0.01

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_check(packed != null, "battle scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var player := _find_ship_by_id(
		scene.get_battle_units(),
		"dd_bluewind"
	)
	_check(player != null, "destroyer weapon test ship spawns")
	if player != null:
		player.team = FactionRelations.PLAYER
		for mount in player.get_weapon_mounts():
			mount.owner_team = player.team
		_test_mount_traverse(player)
		_test_fire_readiness(player, scene.get("allies") as Array)
		_test_cannon_elevation_readiness(player)
		_test_damage_evaluation(player)
		_test_combat_range_and_readiness(
			player,
			scene.get("enemies") as Array
		)
	await _test_torpedo_guidance()
	scene.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.clear_pool()
	_finish()


func _find_ship_by_id(ships: Array, ship_id: String) -> ShipUnit:
	for value in ships:
		var ship := value as ShipUnit
		if ship != null and ship.ship_id == ship_id:
			return ship
	return null


func _test_mount_traverse(player: ShipUnit) -> void:
	var port := player.weapon_mount_root.get_node_or_null("center_port") \
		as TorpedoMount
	var starboard := player.weapon_mount_root.get_node_or_null(
		"center_starboard"
	) as TorpedoMount
	_check(port != null and starboard != null, "side torpedo mounts exist")
	if port == null or starboard == null:
		return
	var front_cannon := player.weapon_mount_root.get_node_or_null("front") \
		as CannonMount
	_check(front_cannon != null, "front cannon mount exists")
	if front_cannon != null:
		var original_minimum := front_cannon.slot_data.traverse_min_degrees
		var original_maximum := front_cannon.slot_data.traverse_max_degrees
		front_cannon.slot_data.traverse_min_degrees = -20.0
		front_cannon.slot_data.traverse_max_degrees = 20.0
		var cannon_side_target := player.to_global(
			Vector3(1800.0, 0.0, 0.0)
		)
		front_cannon.update_traverse_toward(
			cannon_side_target,
			1000.0,
			1.0
		)
		_check(
			_is_relative_yaw_inside_slot(front_cannon),
			"cannon visual rotation respects its traverse limits"
		)
		front_cannon.slot_data.traverse_min_degrees = original_minimum
		front_cannon.slot_data.traverse_max_degrees = original_maximum

	var port_opposite := player.to_global(Vector3(1800.0, 0.0, 0.0))
	port.update_traverse_toward(port_opposite, 1000.0, 1.0)
	_check(
		_is_relative_yaw_inside_slot(port),
		"port mount cannot rotate through the starboard side"
	)
	var starboard_opposite := player.to_global(Vector3(-1800.0, 0.0, 0.0))
	starboard.update_traverse_toward(starboard_opposite, 1000.0, 1.0)
	_check(
		_is_relative_yaw_inside_slot(starboard),
		"starboard mount cannot rotate through the port side"
	)

	var original_rotation := player.rotation
	player.rotation.y += deg_to_rad(47.0)
	var rotated_opposite := player.to_global(Vector3(1800.0, 0.0, 0.0))
	port.update_traverse_toward(rotated_opposite, 1000.0, 1.0)
	_check(
		_is_relative_yaw_inside_slot(port),
		"slot-relative traverse survives ship rotation"
	)
	player.rotation = original_rotation

	var wrap_mount := WeaponMount.new()
	player.weapon_mount_root.add_child(wrap_mount)
	var wrap_slot := ShipWeaponSlotData.new()
	wrap_slot.slot_id = &"wrap_test"
	wrap_slot.traverse_min_degrees = 140.0
	wrap_slot.traverse_max_degrees = -140.0
	var weapon := WeaponDatabase.new().get_weapon(
		"destroyer_cannon"
	).duplicate(true) as WeaponData
	wrap_mount.setup(weapon, wrap_slot, player, player.team)
	var behind := player.to_global(Vector3(0.0, 0.0, 1000.0))
	wrap_mount.update_traverse_toward(behind, 1000.0, 1.0)
	_check(
		wrap_mount.call(&"_is_inside_traverse_arc", behind),
		"wrap traverse accepts a target across the 180 degree boundary"
	)
	var forward := player.to_global(Vector3(0.0, 0.0, -1000.0))
	wrap_mount.update_traverse_toward(forward, 1000.0, 1.0)
	var wrapped_relative := absf(_get_relative_yaw_degrees(wrap_mount))
	_check(
		wrapped_relative >= 139.9,
		"wrap traverse clamps an outside target to the nearest boundary"
	)
	wrap_mount.queue_free()


func _test_fire_readiness(player: ShipUnit, allies: Array) -> void:
	var test_mount := WeaponMount.new()
	player.weapon_mount_root.add_child(test_mount)
	var slot := ShipWeaponSlotData.new()
	slot.slot_id = &"readiness_test"
	slot.traverse_min_degrees = -180.0
	slot.traverse_max_degrees = 180.0
	var weapon := WeaponDatabase.new().get_weapon(
		"destroyer_cannon"
	).duplicate(true) as WeaponData
	weapon.minimum_range_meters = 100.0
	weapon.range_meters = 1000.0
	test_mount.setup(weapon, slot, player, player.team)
	var in_range := player.to_global(Vector3(0.0, 0.0, -500.0))
	_check(
		test_mount.get_fire_readiness_at(in_range)
			== WeaponFireReadiness.State.NO_AIM_POINT,
		"missing aim point reports NO_AIM_POINT"
	)
	test_mount.aim_at(in_range)
	test_mount.reload_left = 1.0
	_check(
		test_mount.get_fire_readiness_at(in_range)
			== WeaponFireReadiness.State.RELOADING,
		"reload reports RELOADING"
	)
	test_mount.reload_left = 0.0
	var too_close := player.to_global(Vector3(0.0, 0.0, -50.0))
	_check(
		test_mount.get_fire_readiness_at(too_close)
			== WeaponFireReadiness.State.INSIDE_MINIMUM_RANGE,
		"minimum range reports INSIDE_MINIMUM_RANGE"
	)
	var too_far := player.to_global(Vector3(0.0, 0.0, -1500.0))
	_check(
		test_mount.get_fire_readiness_at(too_far)
			== WeaponFireReadiness.State.OUT_OF_RANGE,
		"maximum range reports OUT_OF_RANGE"
	)
	slot.traverse_min_degrees = -30.0
	slot.traverse_max_degrees = 30.0
	var outside_arc := player.to_global(Vector3(800.0, 0.0, 0.0))
	_check(
		test_mount.get_fire_readiness_at(outside_arc)
			== WeaponFireReadiness.State.OUTSIDE_TRAVERSE,
		"traverse limit reports OUTSIDE_TRAVERSE"
	)
	slot.traverse_min_degrees = -180.0
	slot.traverse_max_degrees = 180.0
	weapon.projectile_scene = null
	_check(
		test_mount.get_fire_readiness_at(in_range)
			== WeaponFireReadiness.State.NO_PROJECTILE_SCENE,
		"missing projectile reports NO_PROJECTILE_SCENE"
	)
	test_mount.queue_free()

	var port := player.weapon_mount_root.get_node_or_null("center_port") \
		as TorpedoMount
	if port == null:
		return
	var port_target := player.to_global(Vector3(-1500.0, 0.0, 0.0))
	for ally_value in allies:
		var ally := ally_value as ShipUnit
		if ally != null:
			ally.global_position = player.global_position \
				+ Vector3(5000.0, 0.0, 5000.0)
	port.aim_at(port_target)
	port.reload_left = 0.0
	port.rotation.y = port.base_local_yaw_radians + deg_to_rad(25.0)
	_check(
		port.get_fire_readiness_at(port_target)
			== WeaponFireReadiness.State.NOT_ALIGNED,
		"misaligned torpedo mount reports NOT_ALIGNED"
	)
	port.rotation.y = port.base_local_yaw_radians
	var saved_muzzles := port.muzzles.duplicate()
	port.muzzles.clear()
	_check(
		port.get_fire_readiness_at(port_target)
			== WeaponFireReadiness.State.NO_MUZZLE,
		"empty torpedo muzzle list reports NO_MUZZLE"
	)
	port.muzzles.assign(saved_muzzles)
	var saved_projectile_bonus := port.runtime_stats.projectile_count_bonus
	port.runtime_stats.projectile_count_bonus = -port.tube_count
	_check(
		port.get_fire_readiness_at(port_target)
			== WeaponFireReadiness.State.NO_AMMUNITION,
		"zero effective salvo reports NO_AMMUNITION"
	)
	port.runtime_stats.projectile_count_bonus = saved_projectile_bonus
	_check(
		port.get_fire_readiness_at(port_target)
			== WeaponFireReadiness.State.READY,
		"clear and aligned torpedo mount reports READY"
	)
	if not allies.is_empty():
		var blocking_ally := allies[0] as ShipUnit
		blocking_ally.global_position = port.global_position.lerp(
			port_target,
			0.4
		)
		_check(
			port.get_fire_readiness_at(port_target)
				== WeaponFireReadiness.State.FRIENDLY_BLOCKED,
			"friendly hull inside the launch lane reports FRIENDLY_BLOCKED"
		)
		var blocked_distance := port.friendly_lane_half_width_m \
			+ blocking_ally.ship_data.hull_size.x * 0.5 \
			+ port.friendly_lane_safety_margin_m
		blocking_ally.global_position.z += blocked_distance + 20.0
		_check(
			port.get_fire_readiness_at(port_target)
				== WeaponFireReadiness.State.READY,
			"friendly hull outside the weapon lane does not block firing"
		)


func _test_damage_evaluation(player: ShipUnit) -> void:
	var torpedoes := player.combat.get_weapons_by_type(
		WeaponTypes.Type.TORPEDO
	)
	var cannons := player.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)
	_check(torpedoes.size() == 2 and cannons.size() == 2, "weapon groups load")
	if torpedoes.is_empty() or cannons.is_empty():
		return
	var torpedo := torpedoes[0] as TorpedoMount
	var torpedo_data := torpedo.weapon_data.projectile_data \
		as TorpedoProjectileData
	var projectile_damage := torpedo_data.direct_damage \
		+ torpedo_data.explosion_damage
	var expected_salvo := projectile_damage * 3.0
	_check(
		torpedo.get_salvo_projectile_count() == 3,
		"triple launcher reports three salvo projectiles"
	)
	_check_approx(
		torpedo.get_salvo_damage(),
		expected_salvo,
		"torpedo salvo includes every tube"
	)
	_check_approx(
		torpedo.get_sustained_dps(),
		expected_salvo / torpedo.get_reload_seconds(),
		"torpedo sustained DPS uses salvo damage"
	)
	torpedo.reload_left = 1.0
	_check_approx(
		torpedo.get_ready_salvo_damage(),
		0.0,
		"reloading weapon has no ready salvo damage"
	)
	torpedo.reload_left = 0.0
	var cannon := cannons[0]
	_check_approx(
		cannon.get_sustained_dps(),
		cannon.get_projectile_damage() / cannon.get_reload_seconds(),
		"single-shot cannon sustained DPS remains unchanged"
	)
	_test_cannon_bonus_spread(cannon, player)
	_check_approx(
		player.combat.get_total_salvo_damage(WeaponTypes.Type.TORPEDO),
		expected_salvo * float(torpedoes.size()),
		"ShipCombat totals torpedo salvo damage"
	)


func _test_cannon_elevation_readiness(player: ShipUnit) -> void:
	var cannons := player.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)
	if cannons.is_empty():
		return
	var cannon := cannons[0] as CannonMount
	var target := player.to_global(Vector3(0.0, 0.0, -1000.0))
	cannon.aim_at(target)
	cannon.rotation.y = cannon.base_local_yaw_radians
	var original_pitch := cannon.pitch_degrees
	var original_maximum := cannon.max_pitch_degrees
	cannon.pitch_degrees = cannon.min_pitch_degrees
	_check(
		cannon.get_fire_readiness_at(target)
			== WeaponFireReadiness.State.NOT_ELEVATION_ALIGNED,
		"cannon waits for its ballistic elevation"
	)
	cannon.call(&"_turn_toward", target, 10.0)
	_check(
		cannon.get_fire_readiness_at(target)
			== WeaponFireReadiness.State.READY,
		"cannon becomes ready after elevation alignment"
	)
	var unreachable_target := player.to_global(Vector3(0.0, 0.0, -5000.0))
	cannon.aim_at(unreachable_target)
	cannon.max_pitch_degrees = 5.0
	_check(
		cannon.get_fire_readiness_at(unreachable_target)
			== WeaponFireReadiness.State.NO_BALLISTIC_SOLUTION,
		"pitch limits report NO_BALLISTIC_SOLUTION"
	)
	cannon.max_pitch_degrees = original_maximum
	cannon.pitch_degrees = original_pitch
	cannon.aim_at(target)


func _test_cannon_bonus_spread(
		cannon: CannonMount,
		player: ShipUnit
) -> void:
	var original_bonus := cannon.runtime_stats.projectile_count_bonus
	var original_reload := cannon.reload_left
	var captured_projectiles: Array[Node] = []
	var capture := func(projectile: Node) -> void:
		captured_projectiles.append(projectile)
	cannon.fired.connect(capture)
	cannon.runtime_stats.projectile_count_bonus = 1
	cannon.reload_left = 0.0
	var forward_target := player.to_global(Vector3(0.0, 0.0, -1000.0))
	cannon.aim_at(forward_target)
	cannon.rotation.y = cannon.base_local_yaw_radians
	cannon.call(&"_turn_toward", forward_target, 10.0)
	var fired := cannon.fire()
	_check(fired, "bonus projectile cannon salvo fires")
	_check(
		captured_projectiles.size() == 2,
		"projectile count bonus launches a two-shell salvo"
	)
	if captured_projectiles.size() == 2:
		var first := captured_projectiles[0] as Projectile
		var second := captured_projectiles[1] as Projectile
		_check(
			first != null
				and second != null
				and not first.velocity.normalized().is_equal_approx(
					second.velocity.normalized()
				),
			"bonus cannon shells use distinct horizontal spread directions"
		)
	for projectile in captured_projectiles:
		if projectile != null and projectile.has_method(&"despawn"):
			projectile.call(&"despawn")
	if cannon.fired.is_connected(capture):
		cannon.fired.disconnect(capture)
	cannon.runtime_stats.projectile_count_bonus = original_bonus
	cannon.reload_left = original_reload


func _test_combat_range_and_readiness(
		player: ShipUnit,
		enemies: Array
) -> void:
	if enemies.is_empty():
		return
	var enemy := enemies[0] as ShipUnit
	enemy.global_position = player.to_global(Vector3(0.0, 0.0, -1000.0))
	player.combat.set_aim_point(enemy.global_position)
	for mount in player.combat.weapon_mounts:
		mount.reload_left = 1.0
	_check(
		player.combat.is_target_within_any_weapon_range(enemy),
		"pure range query remains true while weapons reload"
	)
	_check(
		not player.combat.can_attack_target_now(enemy),
		"actual attack query is false while all weapons reload"
	)
	_check(
		player.combat.get_best_fire_readiness_for_type(
			enemy,
			WeaponTypes.Type.CANNON
		) == WeaponFireReadiness.State.RELOADING,
		"typed readiness exposes RELOADING"
	)
	for mount in player.combat.weapon_mounts:
		mount.reload_left = 0.0


func _test_torpedo_guidance() -> void:
	var projectile_scene := load(
		"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
	) as PackedScene
	var base_data := load(
		"res://resources/projectiles/destroyer_torpedo.tres"
	).duplicate(true) as TorpedoProjectileData
	_check(projectile_scene != null and base_data != null, "guidance resources load")
	if projectile_scene == null or base_data == null:
		return
	var target := Node3D.new()
	root.add_child(target)
	target.global_position = Vector3(100.0, -2.0, -100.0)
	base_data.max_turn_rate_deg_sec = 45.0
	base_data.guidance_type = TorpedoProjectileData.GuidanceType.NONE
	var straight := _spawn_guidance_torpedo(projectile_scene, base_data, target)
	var straight_yaw := straight.desired_yaw_radians
	straight.call(&"_update_guidance", 1.0)
	_check_approx(
		straight.desired_yaw_radians,
		straight_yaw,
		"NONE guidance ignores target_ref and continues straight"
	)
	_check(straight.target_ref == null, "NONE guidance does not retain a target")
	straight.despawn()

	var passive_data := base_data.duplicate(true) as TorpedoProjectileData
	passive_data.guidance_type = \
		TorpedoProjectileData.GuidanceType.PASSIVE_HOMING
	passive_data.seeker_activation_distance_m = 50.0
	passive_data.seeker_range_m = 50.0
	passive_data.seeker_field_of_view_degrees = 30.0
	var passive := _spawn_guidance_torpedo(
		projectile_scene,
		passive_data,
		target
	)
	passive.call(&"_update_guidance", 1.0)
	_check_approx(
		passive.desired_yaw_radians,
		0.0,
		"passive seeker waits for activation distance"
	)
	passive.travelled_distance_m = 60.0
	passive.call(&"_update_guidance", 1.0)
	_check_approx(
		passive.desired_yaw_radians,
		0.0,
		"passive seeker holds heading outside seeker range"
	)
	passive_data.seeker_range_m = 1000.0
	passive.call(&"_update_guidance", 1.0)
	_check_approx(
		passive.desired_yaw_radians,
		0.0,
		"passive seeker holds heading outside seeker FOV"
	)
	passive_data.seeker_field_of_view_degrees = 180.0
	passive.call(&"_update_guidance", 1.0)
	_check(
		not is_zero_approx(passive.desired_yaw_radians),
		"PASSIVE_HOMING turns toward a valid seeker target"
	)
	passive.despawn()
	target.queue_free()
	await process_frame


func _spawn_guidance_torpedo(
		projectile_scene: PackedScene,
		data: TorpedoProjectileData,
		target: Node3D
) -> TorpedoProjectile:
	var torpedo := projectile_scene.instantiate() as TorpedoProjectile
	root.add_child(torpedo)
	torpedo.setup_projectile_data(data)
	var context := ProjectileLaunchContext.new()
	context.source_team = &"test"
	context.source_weapon_id = &"guidance_test"
	context.initial_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 0.0, 0.0)
	)
	context.target = target
	torpedo.launch_with_context(context)
	return torpedo


func _is_relative_yaw_inside_slot(mount: WeaponMount) -> bool:
	return bool(mount.call(
		&"_is_angle_inside_limits",
		_get_relative_yaw_degrees(mount),
		mount.slot_data.traverse_min_degrees,
		mount.slot_data.traverse_max_degrees
	))


func _get_relative_yaw_degrees(mount: WeaponMount) -> float:
	return wrapf(
		rad_to_deg(mount.rotation.y - mount.base_local_yaw_radians),
		-180.0,
		180.0
	)


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


func _finish() -> void:
	for failure in _failures:
		push_error("WEAPON READINESS TEST: %s" % failure)
	if _failures.is_empty():
		print("WEAPON_READINESS_TEST PASS")
	quit(0 if _failures.is_empty() else 1)
