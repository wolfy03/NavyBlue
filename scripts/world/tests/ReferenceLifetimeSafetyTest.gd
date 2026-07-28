extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_object_pool_skips_freed_entries()
	_test_spawn_system_skips_freed_units()
	_test_battle_scene_prunes_freed_references()
	_test_fleet_candidate_cache_prunes_freed_ships()
	_test_target_selector_skips_freed_candidates()
	_test_hud_skips_freed_indicators()
	_test_selection_and_debug_lists_prune_freed_nodes()
	_test_splash_pool_prunes_freed_effects()
	_test_fleet_damage_event_skips_freed_ships()
	_test_ship_combat_skips_freed_mounts()
	for failure in _failures:
		push_error("REFERENCE LIFETIME TEST: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_object_pool_skips_freed_entries() -> void:
	var object_pool := root.get_node_or_null("ObjectPool")
	_check(object_pool != null, "ObjectPool autoload exists")
	if object_pool == null:
		return
	object_pool.clear_pool()
	var packed_scene := PackedScene.new()
	var template := Node3D.new()
	_check(packed_scene.pack(template) == OK, "temporary pooled scene packs")
	template.free()
	var parent := Node3D.new()
	root.add_child(parent)
	var pooled: Node = object_pool.spawn(packed_scene, parent)
	_check(pooled != null, "ObjectPool creates initial node")
	if pooled != null:
		_check(object_pool.recycle(pooled), "ObjectPool recycles initial node")
		_check(
			pooled.get_parent() == object_pool,
			"ObjectPool owns recycled nodes inside the SceneTree"
		)
		_check(
			object_pool.recycle(pooled),
			"ObjectPool ignores duplicate recycle requests"
		)
		pooled.free()
	var replacement: Node = object_pool.spawn(packed_scene, parent)
	_check(
		replacement != null and is_instance_valid(replacement),
		"ObjectPool skips a freed pooled entry"
	)
	if replacement != null and is_instance_valid(replacement):
		object_pool.recycle(replacement)
		_check(
			replacement.get_parent() == object_pool,
			"ObjectPool owns replacement nodes after recycle"
		)
	object_pool.clear_pool()
	parent.queue_free()
	await process_frame


func _test_spawn_system_skips_freed_units() -> void:
	var spawn_system := SpawnSystem.new()
	var stale_unit := Node.new()
	spawn_system.spawned_units.append(stale_unit)
	stale_unit.free()
	spawn_system.clear_spawned_units()
	_check(
		spawn_system.spawned_units.is_empty(),
		"SpawnSystem clears freed unit references"
	)
	spawn_system.free()


func _test_battle_scene_prunes_freed_references() -> void:
	var battle_scene := BattleScene.new()
	var stale_unit := Node3D.new()
	battle_scene._battle_units.append(stale_unit)
	stale_unit.free()
	_check(
		battle_scene.get_battle_units().is_empty(),
		"BattleScene prunes freed battle units"
	)
	var stale_controller := FleetAIController.new()
	battle_scene._fleet_controllers[&"test::stale"] = stale_controller
	stale_controller.free()
	_check(
		battle_scene.get_fleet_controllers().is_empty(),
		"BattleScene skips freed fleet controllers"
	)
	battle_scene.free()


func _test_fleet_candidate_cache_prunes_freed_ships() -> void:
	var fleet := FleetAIController.new()
	var stale_ship := ShipUnit.new()
	fleet._hostile_candidate_cache.append(stale_ship)
	stale_ship.free()
	var candidates: Array[ShipUnit] = fleet._get_hostile_candidates()
	_check(candidates.is_empty(), "Fleet cache does not return freed ships")
	_check(
		fleet._hostile_candidate_cache.is_empty(),
		"Fleet cache removes freed ship references"
	)
	fleet.free()


func _test_target_selector_skips_freed_candidates() -> void:
	var selector := ShipTargetSelector.new()
	var owner_ship := Node3D.new()
	var stale_ship := ShipUnit.new()
	var candidates: Array = [stale_ship]
	stale_ship.free()
	_check(
		selector.collect_valid_candidates(owner_ship, candidates).is_empty(),
		"ShipTargetSelector validates before casting a candidate"
	)
	owner_ship.free()


func _test_hud_skips_freed_indicators() -> void:
	var hud := HUD.new()
	var stale_indicator := ShipStatusIndicator.new()
	var indicator_id := stale_indicator.get_instance_id()
	hud._ship_indicators[indicator_id] = stale_indicator
	stale_indicator.free()
	hud._remove_ship_indicator(indicator_id)
	_check(
		not hud._ship_indicators.has(indicator_id),
		"HUD removes a freed indicator reference"
	)
	hud.free()


func _test_selection_and_debug_lists_prune_freed_nodes() -> void:
	var input_manager := PlayerInputManager.new()
	var stale_selection := Node3D.new()
	input_manager.selected_ships.append(stale_selection)
	stale_selection.free()
	input_manager._prune_selection()
	_check(
		input_manager.selected_ships.is_empty(),
		"PlayerInputManager prunes freed selections"
	)
	input_manager.free()

	var renderer := NavigationDebugRenderer.new()
	var stale_debug_ship := Node3D.new()
	renderer._ships.append(stale_debug_ship)
	stale_debug_ship.free()
	renderer._draw_ship_navigation(stale_debug_ship)
	renderer._prune_ships()
	_check(
		renderer._ships.is_empty(),
		"NavigationDebugRenderer prunes freed ships"
	)
	renderer._mesh_instance.free()
	renderer.free()


func _test_splash_pool_prunes_freed_effects() -> void:
	var splash_pool := SplashEffectPool.new()
	var stale_effect := Node3D.new()
	splash_pool._splashes.append(stale_effect)
	stale_effect.free()
	_check(
		splash_pool.get_active_splash_count() == 0,
		"SplashEffectPool skips freed effect references"
	)
	_check(
		splash_pool._splashes.is_empty(),
		"SplashEffectPool removes freed effect references"
	)
	splash_pool.free()


func _test_fleet_damage_event_skips_freed_ships() -> void:
	var fleet := FleetAIController.new()
	var stale_damaged_ship := ShipUnit.new()
	stale_damaged_ship.free()
	fleet._on_ship_damaged(stale_damaged_ship, 10.0, {})

	var damaged_ship := ShipUnit.new()
	var context := FleetMemberContext.new().setup(damaged_ship)
	fleet._member_contexts[damaged_ship.get_instance_id()] = context
	var stale_attacker := ShipUnit.new()
	var damage_info := {"attacker_ship": stale_attacker}
	stale_attacker.free()
	fleet._on_ship_damaged(damaged_ship, 10.0, damage_info)
	_check(true, "Fleet damage events tolerate freed ship references")
	damaged_ship.free()
	fleet.free()


func _test_ship_combat_skips_freed_mounts() -> void:
	var combat := ShipCombat.new()
	var stale_mount := WeaponMount.new()
	combat.weapon_mounts.append(stale_mount)
	stale_mount.free()
	_check(
		combat.get_primary_weapon_range_m() == 0.0,
		"ShipCombat skips freed weapon mounts"
	)
	_check(
		combat.get_weapons_by_type(WeaponTypes.Type.CANNON).is_empty(),
		"ShipCombat does not return freed weapon mounts"
	)
	combat.free()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
