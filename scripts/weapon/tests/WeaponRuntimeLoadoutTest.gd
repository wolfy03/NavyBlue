extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_runtime_stats_serialization()
	_test_loadout_normalize_validate_and_repair()
	await _test_runtime_mount_isolation_and_rebuild()
	for failure in _failures:
		push_error("WEAPON_RUNTIME_LOADOUT_TEST: %s" % failure)
	if _failures.is_empty():
		print("WEAPON_RUNTIME_LOADOUT_TEST PASS")
	quit(0 if _failures.is_empty() else 1)


func _test_runtime_stats_serialization() -> void:
	var stats := WeaponRuntimeStats.new()
	stats.reload_multiplier = 0.8
	stats.damage_multiplier = 1.25
	stats.range_multiplier = 1.1
	stats.projectile_speed_multiplier = 1.2
	stats.projectile_count_bonus = 2
	stats.traverse_speed_multiplier = 1.15
	stats.flooding_chance_bonus = 0.1
	var restored := WeaponRuntimeStats.from_dictionary(stats.to_dictionary())
	_check(is_equal_approx(restored.reload_multiplier, 0.8), "reload multiplier serializes")
	_check(is_equal_approx(restored.damage_multiplier, 1.25), "damage multiplier serializes")
	_check(restored.projectile_count_bonus == 2, "projectile count bonus serializes")
	var copy := restored.duplicate_stats()
	copy.damage_multiplier = 3.0
	_check(
		not is_equal_approx(restored.damage_multiplier, copy.damage_multiplier),
		"runtime stats copies do not share mutable state"
	)


func _test_loadout_normalize_validate_and_repair() -> void:
	var ship_data := ShipDatabase.new().get_ship("dd_bluewind")
	var database := WeaponDatabase.new()
	var valid := ShipWeaponLoadout.from_ship_data(ship_data)
	_check(
		valid.validate_against_ship(ship_data, database).is_empty(),
		"default loadout validates"
	)

	var malformed := ShipWeaponLoadout.new()
	malformed.entries.append(_entry(&"front", "missing_weapon"))
	malformed.entries.append(_entry(&"front", "destroyer_cannon"))
	malformed.entries.append(_entry(&"center_port", "destroyer_cannon"))
	malformed.entries.append(_entry(&"unknown_slot", "destroyer_cannon"))
	_check(
		not malformed.validate_against_ship(ship_data, database).is_empty(),
		"validation reports duplicate, incompatible, and unknown entries"
	)
	malformed.normalize()
	_check(
		malformed.get_weapon_id(&"front") == "destroyer_cannon",
		"normalization keeps the last duplicate value"
	)
	var warnings := malformed.repair_against_ship(ship_data, database)
	_check(not warnings.is_empty(), "repair reports its changes")
	_check(
		malformed.get_weapon_id(&"center_port")
			== "destroyer_torpedo_launcher",
		"repair falls back to the slot default"
	)
	_check(
		malformed.get_weapon_id(&"unknown_slot").is_empty(),
		"repair removes unknown slots"
	)
	_check(
		malformed.validate_against_ship(ship_data, database).is_empty(),
		"repaired loadout validates"
	)

	var migrated := ShipWeaponLoadout.from_dictionary({
		"entries": [
			{"slot_id": "rear", "weapon_id": "missing_weapon"},
			{"slot_id": "rear", "weapon_id": "destroyer_cannon"},
		],
	})
	_check(
		migrated.entries.size() == 1
			and migrated.get_weapon_id(&"rear") == "destroyer_cannon",
		"dictionary migration normalizes duplicate slots deterministically"
	)


func _test_runtime_mount_isolation_and_rebuild() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	var scene := packed.instantiate() if packed != null else null
	_check(scene != null, "battle scene instantiates for runtime weapon test")
	if scene == null:
		return
	root.add_child(scene)
	await process_frame
	await physics_frame
	var player := scene.get("player_ship") as ShipUnit
	var enemies: Array = scene.get("enemies")
	var enemy_destroyer: ShipUnit
	for enemy_value in enemies:
		var enemy := enemy_value as ShipUnit
		if enemy != null and enemy.ship_id == "dd_bluewind":
			enemy_destroyer = enemy
			break
	_check(player != null and enemy_destroyer != null, "runtime test resolves two destroyers")
	if player == null or enemy_destroyer == null:
		scene.queue_free()
		await process_frame
		return

	var player_front := _find_mount(player, &"front")
	var enemy_front := _find_mount(enemy_destroyer, &"front")
	_check(player_front != null and enemy_front != null, "front cannon mounts exist")
	if player_front == null or enemy_front == null:
		scene.queue_free()
		await process_frame
		return
	var shared_weapon_data := player_front.weapon_data
	_check(
		player_front.weapon_data == enemy_front.weapon_data,
		"ships share immutable WeaponData resources"
	)

	var stats := WeaponRuntimeStats.new()
	stats.reload_multiplier = 0.5
	stats.damage_multiplier = 1.5
	stats.range_multiplier = 1.2
	stats.projectile_speed_multiplier = 1.1
	stats.projectile_count_bonus = 1
	stats.traverse_speed_multiplier = 1.25
	player.set_weapon_runtime_stats(&"front", stats)
	player_front = _find_mount(player, &"front")
	_check(
		is_equal_approx(
			player_front.get_reload_seconds(),
			shared_weapon_data.reload_seconds * 0.5
		),
		"runtime reload multiplier is applied"
	)
	_check(
		is_equal_approx(
			player_front.get_range_m(),
			shared_weapon_data.range_meters * 1.2
		),
		"runtime range multiplier is applied"
	)
	_check(
		player_front.get_salvo_projectile_count() == 2,
		"runtime projectile count bonus affects cannon salvo"
	)
	_check(
		is_equal_approx(
			player_front.get_muzzle_velocity_vector().length(),
			shared_weapon_data.muzzle_velocity * 1.1
		),
		"runtime projectile speed multiplier affects cannon launch velocity"
	)
	_check(
		is_equal_approx(
			player_front.get_modified_traverse_speed(10.0),
			12.5
		),
		"runtime traverse speed multiplier is applied"
	)
	_check(
		is_equal_approx(
			player_front.get_projectile_damage(),
			shared_weapon_data.projectile_data.damage * 1.5
		),
		"runtime damage multiplier affects salvo evaluation"
	)
	_check(
		is_equal_approx(enemy_front.runtime_stats.damage_multiplier, 1.0),
		"runtime modifiers do not leak to another ship"
	)
	_check(
		is_equal_approx(shared_weapon_data.reload_seconds, 4.5),
		"runtime modifiers do not mutate WeaponData"
	)
	var torpedo_stats := WeaponRuntimeStats.new()
	torpedo_stats.projectile_count_bonus = 8
	player.set_weapon_runtime_stats(&"center_port", torpedo_stats)
	var torpedo_mount := _find_mount(player, &"center_port") as TorpedoMount
	_check(
		torpedo_mount != null
			and torpedo_mount.get_salvo_projectile_count()
				== torpedo_mount.muzzles.size(),
		"torpedo projectile count bonus is capped by available muzzles"
	)

	var front_slot := _find_slot(player.ship_data, &"front")
	front_slot.allowed_weapon_types = [
		WeaponTypes.Type.CANNON,
		WeaponTypes.Type.TORPEDO,
	]
	player.combat.set_target(enemy_destroyer)
	var previous_aim := enemy_destroyer.global_position
	player.combat.set_aim_point(previous_aim)
	var old_mounts := player.get_weapon_mounts().duplicate()
	var torpedo_result := player.equip_weapon(
		&"front",
		"destroyer_torpedo_launcher"
	)
	_check(torpedo_result.valid, "compatible runtime cannon-to-torpedo swap succeeds")
	_check(player.combat.target == enemy_destroyer, "weapon rebuild preserves target")
	_check(
		player.combat.has_aim_point
			and player.combat.aim_point.is_equal_approx(previous_aim),
		"weapon rebuild preserves aim point"
	)
	var swapped_mount := _find_mount(player, &"front")
	_check(
		swapped_mount != null
			and swapped_mount.get_weapon_type() == WeaponTypes.Type.TORPEDO,
		"runtime swap registers the new mount once"
	)
	_check(
		swapped_mount != null
			and is_equal_approx(swapped_mount.runtime_stats.damage_multiplier, 1.5),
		"slot runtime stats survive weapon replacement"
	)
	_check(
		old_mounts.all(
			func(mount): return not is_instance_valid(mount) \
				or mount.get_parent() == null
		),
		"old mounts are detached during rebuild"
	)
	var cannon_result := player.equip_weapon(&"front", "destroyer_cannon")
	_check(cannon_result.valid, "compatible runtime torpedo-to-cannon swap succeeds")
	_check(
		not player.equip_weapon(&"missing_slot", "destroyer_cannon").valid,
		"unknown slots are rejected safely"
	)
	_check(
		not player.equip_weapon(&"front", "missing_weapon").valid,
		"unknown weapons are rejected safely"
	)

	var run_manager := root.get_node_or_null("RunManager")
	if run_manager != null:
		run_manager.capture_player_ship(player)
		var saved_stats: Dictionary = run_manager.player_ship_state.get(
			"weapon_runtime_stats",
			{}
		)
		var restored_stats := WeaponRuntimeStats.from_dictionary(
			saved_stats.get("front", {})
		)
		_check(
			is_equal_approx(restored_stats.damage_multiplier, 1.5),
			"RunManager captures JSON-safe slot runtime stats"
		)
		_check(
			not JSON.stringify(run_manager.player_ship_state).is_empty(),
			"captured loadout and runtime stats serialize as JSON"
		)

	scene.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.clear_pool()


func _entry(slot_id: StringName, weapon_id: String) -> WeaponLoadoutEntryData:
	var entry := WeaponLoadoutEntryData.new()
	entry.slot_id = slot_id
	entry.weapon_id = weapon_id
	return entry


func _find_slot(
		ship_data: ShipData,
		slot_id: StringName
) -> ShipWeaponSlotData:
	for slot in ship_data.weapon_slots:
		if slot != null and slot.slot_id == slot_id:
			return slot
	return null


func _find_mount(ship: ShipUnit, slot_id: StringName) -> WeaponMount:
	for mount in ship.get_weapon_mounts():
		if is_instance_valid(mount) and mount.slot_data != null \
				and mount.slot_data.slot_id == slot_id:
			return mount
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
