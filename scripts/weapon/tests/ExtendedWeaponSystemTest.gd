extends SceneTree

const WEAPON_STAGE: StageData = preload(
	"res://resources/stages/tests/weapon_combat_test.tres"
)

var _failures: Array[String] = []


class MissingWeaponDatabase:
	extends WeaponDatabase

	func get_weapon(_id: String) -> WeaponData:
		return null


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_resource_model()
	await _test_torpedo_physics_stability()
	await _test_battle_weapon_flow()
	for failure in _failures:
		push_error("EXTENDED WEAPON TEST: %s" % failure)
	if _failures.is_empty():
		print("EXTENDED_WEAPON_SYSTEM_TEST PASS")
	quit(0 if _failures.is_empty() else 1)


func _test_resource_model() -> void:
	_check(WeaponTypes.Type.CANNON == 0, "cannon enum value remains stable")
	_check(WeaponTypes.Type.TORPEDO == 1, "torpedo enum value remains stable")
	_check(WeaponTypes.SlotSize.MEDIUM == 1, "slot size enum value remains stable")
	_test_legacy_mount_null_safety()
	var ship_data := ShipDatabase.new().get_ship("dd_bluewind")
	_check(ship_data != null, "destroyer ShipData loads")
	if ship_data == null:
		return
	_check(ship_data.weapon_slots.size() == 4, "destroyer exposes four weapon slots")
	var loadout := ShipWeaponLoadout.from_ship_data(ship_data)
	_check(
		loadout.get_weapon_id(&"center_port") == "destroyer_torpedo_launcher",
		"default loadout records the port torpedo launcher"
	)
	var serialized := loadout.to_dictionary()
	var restored := ShipWeaponLoadout.from_dictionary(serialized)
	_check(
		restored.get_weapon_id(&"center_starboard")
			== "destroyer_torpedo_launcher",
		"loadout survives dictionary serialization"
	)
	var port_slot := _find_slot(ship_data, &"center_port")
	var weapon_database := WeaponDatabase.new()
	var cannon := weapon_database.get_weapon("destroyer_cannon")
	var torpedo := weapon_database.get_weapon("destroyer_torpedo_launcher")
	_check(
		not WeaponMountValidator.can_mount(port_slot, cannon),
		"torpedo slot rejects a cannon"
	)
	_check(
		WeaponMountValidator.can_mount(port_slot, torpedo),
		"torpedo slot accepts its launcher"
	)
	_check(
		torpedo.mount_scene != null
			and torpedo.projectile_data is TorpedoProjectileData,
		"torpedo WeaponData owns mount and projectile resources"
	)


func _test_legacy_mount_null_safety() -> void:
	var builder := ShipVisualBuilder.new()
	builder.diagnostics_enabled = false
	var ship_data := ShipData.new()
	ship_data.id = "legacy_test_ship"
	ship_data.default_weapon_id = "missing_legacy_weapon"
	var no_ship: Array = builder.call(
		&"_build_legacy_turrets",
		null,
		&"test",
		null,
		null
	)
	_check(no_ship.is_empty(), "legacy builder rejects missing ShipData")
	var no_root: Array = builder.call(
		&"_build_legacy_turrets",
		ship_data,
		&"test",
		null,
		null
	)
	_check(no_root.is_empty(), "legacy builder rejects missing mount root")
	var mount_root := Node3D.new()
	builder.weapon_mount_root = mount_root
	builder.weapon_database = MissingWeaponDatabase.new()
	var no_weapon: Array = builder.call(
		&"_build_legacy_turrets",
		ship_data,
		&"test",
		null,
		null
	)
	_check(no_weapon.is_empty(), "legacy builder rejects missing WeaponData")
	mount_root.free()
	builder.free()


func _test_torpedo_physics_stability() -> void:
	var torpedo_scene := load(
		"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
	) as PackedScene
	var data := load(
		"res://resources/projectiles/destroyer_torpedo.tres"
	).duplicate(true) as TorpedoProjectileData
	_check(torpedo_scene != null and data != null, "torpedo physics resources load")
	if torpedo_scene == null or data == null:
		return
	data.arming_distance_m = 1.0
	var torpedo := torpedo_scene.instantiate() as TorpedoProjectile
	root.add_child(torpedo)
	var context := ProjectileLaunchContext.new()
	context.source_team = &"test"
	context.source_weapon_id = &"physics_test_torpedo"
	context.initial_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	torpedo.configure(data, BattleTestServices.create(self))
	torpedo.launch(context)
	var expected_depth := -data.running_depth_m
	var initial_position := torpedo.global_position
	var maximum_depth_error := 0.0
	for _frame in 20:
		await physics_frame
		maximum_depth_error = maxf(
			maximum_depth_error,
			absf(torpedo.global_position.y - expected_depth)
		)
	var movement_distance := initial_position.distance_to(torpedo.global_position)
	_check(movement_distance > 1.0, "torpedo advances through RigidBody integration")
	_check(maximum_depth_error < 0.05, "torpedo maintains a stable running depth")
	_check(torpedo.travelled_distance_m > 0.0, "torpedo records actual movement")
	_check(torpedo.armed, "torpedo arms from actual travelled distance")
	_check(
		torpedo.previous_position.distance_to(torpedo.global_position) < 1.0,
		"torpedo previous position tracks the last physical segment"
	)

	torpedo.target_ref = weakref(torpedo)
	torpedo.desired_yaw_radians = 1.0
	torpedo.linear_velocity = Vector3.ONE
	torpedo.angular_velocity = Vector3.ONE
	torpedo.despawn()
	_check(
		_is_stored_in_object_pool(torpedo),
		"torpedo returns to ObjectPool"
	)
	_check(
		torpedo.target_ref == null
			and not torpedo.impact_processed
			and not torpedo.armed
			and is_zero_approx(torpedo.travelled_distance_m)
			and is_zero_approx(torpedo.age_seconds)
			and is_zero_approx(torpedo.speed_mps)
			and is_zero_approx(torpedo.desired_yaw_radians)
			and torpedo.linear_velocity.is_zero_approx()
			and torpedo.angular_velocity.is_zero_approx(),
		"recycled torpedo clears all transient physics state"
	)

	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		var reused := object_pool.spawn(torpedo_scene, root) as TorpedoProjectile
		_check(reused == torpedo, "ObjectPool reuses the reset torpedo")
		if reused != null:
			_check(
				reused.previous_position == reused.global_position
					and reused.target_ref == null
					and reused.linear_velocity.is_zero_approx(),
				"spawned torpedo starts without stale state"
			)
			reused.despawn()


func _test_battle_weapon_flow() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_check(packed != null, "battle scene loads")
	if packed == null:
		return
	var scene := packed.instantiate() as BattleScene
	scene.stage_override = WEAPON_STAGE
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED

	var player := scene.player_ship as ShipUnit
	_check(player != null, "battle spawns a destroyer weapon test ship")
	if player == null:
		scene.queue_free()
		await process_frame
		return
	var mounts := player.get_weapon_mounts()
	var cannons := player.combat.get_weapons_by_type(WeaponTypes.Type.CANNON)
	var torpedoes := player.combat.get_weapons_by_type(WeaponTypes.Type.TORPEDO)
	_check(mounts.size() == 4, "ShipVisualBuilder creates every destroyer mount")
	_check(cannons.size() == 2, "ShipCombat exposes two cannon mounts")
	_check(torpedoes.size() == 2, "ShipCombat exposes two torpedo mounts")
	var aim_preview := player.get_node_or_null("TorpedoAimPreview") \
		as TorpedoAimPreview
	var port_mount := player.weapon_mount_root.get_node_or_null("center_port") \
		as TorpedoMount
	_check(aim_preview != null, "player ship includes a torpedo aim preview")
	if aim_preview != null:
		var preview_aim_point := player.global_position \
			+ -port_mount.global_transform.basis.z.normalized() * 1200.0 \
			if port_mount != null \
			else player.global_position + Vector3(-1200.0, 0.0, 0.0)
		preview_aim_point.y = player.global_position.y
		player.combat.set_aim_point(preview_aim_point)
		aim_preview.call(&"_refresh_preview")
		_check(
			aim_preview.visible
				and (aim_preview.mesh as ImmediateMesh).get_surface_count() > 0,
			"torpedo arc and path preview builds a visible line surface"
		)

	_check(port_mount != null, "port torpedo mount uses TorpedoMount scene")
	if port_mount != null:
		var aim_point := port_mount.global_position \
			+ -port_mount.global_transform.basis.z.normalized() * 1200.0
		aim_point.y = player.global_position.y
		port_mount.aim_at(aim_point)
		port_mount.update_traverse_toward(
			aim_point,
			port_mount.yaw_speed_degrees,
			1.0
		)
		var projectiles := scene.get_node_or_null("Projectiles")
		var before_count := _count_torpedoes(projectiles)
		var fired := port_mount.fire()
		var after_count := _count_torpedoes(projectiles)
		_check(fired, "torpedo mount fires inside its side arc")
		_check(after_count - before_count == 3, "triple launcher creates three torpedoes")
		var spawned := _find_torpedo_from_ship(projectiles, player.get_instance_id())
		_check(spawned != null, "launched torpedo carries its source ship")
		if spawned != null:
			_check(
				not str(spawned.get_meta("pool_key", "")).is_empty(),
				"torpedo is created through ObjectPool"
			)
			var segment_start := spawned.global_position
			var segment_direction := -spawned.global_transform.basis.z.normalized()
			spawned.global_position += segment_direction * (
				spawned.torpedo_data.arming_distance_m + 1.0
			)
			spawned.previous_position = segment_start
			spawned.call(&"_physics_process", 0.1)
			_check(spawned.armed, "torpedo arms after travelling its safety distance")
			spawned.despawn()
			_check(
				_is_stored_in_object_pool(spawned),
				"torpedo returns to ObjectPool"
			)

	var target := _find_ship_by_id(scene.get("enemies"), "bb_ironwake")
	_check(target != null, "damage test finds the enemy battleship")
	if target != null:
		var collision_data := load(
			"res://resources/projectiles/destroyer_torpedo.tres"
		).duplicate(true) as TorpedoProjectileData
		collision_data.direct_damage = 10.0
		collision_data.explosion_damage = 0.0
		collision_data.flooding_chance = 0.0
		collision_data.arming_distance_m = 0.0
		var collision_scene := load(
			"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
		) as PackedScene
		var collision_torpedo := collision_scene.instantiate() \
			as TorpedoProjectile
		scene.get_node("Projectiles").add_child(collision_torpedo)
		var context := ProjectileLaunchContext.new()
		context.source_ship = player
		context.source_team = player.team
		context.source_weapon_id = &"destroyer_torpedo_launcher"
		context.initial_transform = Transform3D(
			Basis.IDENTITY,
			target.global_position + Vector3(0.0, -2.0, 200.0)
		)
		collision_torpedo.configure(
			collision_data,
			BattleTestServices.create(self)
		)
		collision_torpedo.launch(context)
		collision_torpedo.armed = true
		collision_torpedo.previous_position = target.global_position \
			+ Vector3(0.0, -2.0, 200.0)
		collision_torpedo.global_position = target.global_position \
			+ Vector3(0.0, -2.0, -200.0)
		var hp_before_collision := target.get_current_hp()
		var swept_hit: bool = collision_torpedo.call(
			&"_try_process_ship_proximity",
			collision_torpedo.previous_position,
			collision_torpedo.global_position
		)
		_check(swept_hit, "underwater swept path intersects the hull")
		_check(
			target.get_current_hp() < hp_before_collision,
			"underwater swept hit applies torpedo damage"
		)

		var data := load(
			"res://resources/projectiles/destroyer_torpedo.tres"
		).duplicate(true) as TorpedoProjectileData
		data.flooding_chance = 1.0
		var hit_info := HitInfo.new()
		hit_info.target_ship = target
		hit_info.hit_position = target.global_position
		hit_info.hit_normal = Vector3.BACK
		hit_info.shell_direction = Vector3.FORWARD
		hit_info.armor_part = ArmorPart.Type.BELT
		hit_info.damage_type = DamageType.Type.TORPEDO
		hit_info.torpedo_data = data
		hit_info.set_damage_source(
			player,
			player.get_instance_id(),
			&"destroyer_torpedo_launcher"
		)
		var hp_before := target.get_current_hp()
		var result := DamageResolver.resolve_hit(hit_info)
		_check(result.resolved and result.final_damage > 0.0, "torpedo damage resolves")
		_check(target.get_current_hp() < hp_before, "torpedo applies immediate damage")
		_check(
			result.flooding_triggered and target.damage_status.is_flooding(),
			"torpedo starts flooding"
		)
		var hp_before_flooding := target.get_current_hp()
		target.damage_status.call(&"_physics_process", 1.0)
		_check(
			target.get_current_hp() < hp_before_flooding,
			"flooding applies damage over time"
		)

	var run_manager := root.get_node_or_null("RunManager")
	if run_manager != null:
		run_manager.capture_player_ship(player)
		var saved_loadout: Dictionary = run_manager.player_ship_state.get(
			"weapon_loadout",
			{}
		)
		var restored_loadout := ShipWeaponLoadout.from_dictionary(saved_loadout)
		_check(
			restored_loadout.get_weapon_id(&"center_port")
				== "destroyer_torpedo_launcher",
			"RunManager captures slot loadout as JSON-safe ids"
		)

	scene.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.clear_pool()


func _find_slot(
		ship_data: ShipData,
		slot_id: StringName
) -> ShipWeaponSlotData:
	for slot in ship_data.weapon_slots:
		if slot != null and slot.slot_id == slot_id:
			return slot
	return null


func _count_torpedoes(parent: Node) -> int:
	if parent == null:
		return 0
	var count := 0
	for child in parent.get_children():
		if child is TorpedoProjectile:
			count += 1
	return count


func _is_stored_in_object_pool(node: Node) -> bool:
	var object_pool := root.get_node_or_null("ObjectPool")
	return node != null \
		and is_instance_valid(node) \
		and object_pool != null \
		and node.get_parent() == object_pool \
		and bool(node.get_meta("in_object_pool", false))


func _find_torpedo_from_ship(
		parent: Node,
		source_instance_id: int
) -> TorpedoProjectile:
	if parent == null:
		return null
	for child in parent.get_children():
		var torpedo := child as TorpedoProjectile
		if torpedo != null \
				and torpedo.source_ship_instance_id == source_instance_id:
			return torpedo
	return null


func _find_ship_by_id(ships: Array, ship_id: String) -> ShipUnit:
	for value in ships:
		var ship := value as ShipUnit
		if ship != null and ship.ship_id == ship_id:
			return ship
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
