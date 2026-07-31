extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/weapon_combat_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await process_frame
	var presentation := battle.ship_weapon_preview_presentation
	var cruiser := _find_ship(battle.enemies, &"cl_tidebreaker")
	_check(presentation != null, "battle composes turret presentation")
	_check(cruiser != null, "fixture provides a three-cannon cruiser")
	if presentation == null or cruiser == null:
		await _finish(battle)
		return
	cruiser.player_controlled = true
	battle.input_manager.controlled_ship = cruiser
	battle.input_manager.selection_coordinator.select_only(cruiser)
	presentation.refresh_now()
	var mounts := cruiser.get_player_cannon_preview_mounts()
	_check(mounts.size() == 3, "cruiser exposes three cannon mounts")
	var targets := [10000.0, 12000.0, 15000.0]
	for index in mini(mounts.size(), targets.size()):
		var base_range := mounts[index].weapon_data.range_meters
		mounts[index].runtime_stats.range_multiplier = \
			targets[index] / base_range
	presentation.refresh_now()
	_verify_one_preview_per_mount(presentation, mounts, targets)
	_verify_material_contract(presentation, mounts)
	_verify_mode_and_pool_reuse(battle, presentation, cruiser)
	await _verify_mount_removal(presentation, mounts)
	await _finish(battle)


func _verify_one_preview_per_mount(
		presentation: ShipWeaponPreviewPresentation,
		mounts: Array[WeaponMount],
		targets: Array
) -> void:
	var previews := presentation.get_active_previews()
	_check(
		previews.size() == mounts.size(),
		"presentation creates one preview per cannon mount"
	)
	for preview in previews:
		var mount := preview.get_bound_mount()
		var index := mounts.find(mount)
		_check(index >= 0, "preview is bound to an authoritative mount")
		if index < 0:
			continue
		var length := preview.line_mesh.scale.z
		_check(
			is_equal_approx(length, float(targets[index])),
			"preview line uses mount %d individual range" % index
		)
		var expected_origin := mount.get_preview_muzzle_position()
		var reconstructed_origin := preview.global_position \
			+ preview.global_basis.z * length * 0.5
		_check(
			reconstructed_origin.distance_to(expected_origin) < 0.1,
			"preview line starts at mount %d muzzle" % index
		)
		_check(
			(-preview.global_basis.z).angle_to(
				mount.get_projectile_launch_direction_world()
			) < 0.001,
			"preview line follows mount %d barrel direction" % index
		)
		_check(
			preview.line_mesh.mesh is BoxMesh \
				and not preview.is_processing() \
				and not preview.is_physics_processing(),
			"preview uses a passive reusable BoxMesh"
		)


func _verify_material_contract(
		presentation: ShipWeaponPreviewPresentation,
		mounts: Array[WeaponMount]
) -> void:
	if mounts.is_empty():
		return
	var first := mounts[0]
	var cannon := first as CannonMount
	var owner_ship := first.get_owner_ship()
	if cannon != null and owner_ship != null:
		var target := owner_ship.to_global(
			Vector3(0.0, 0.0, -1000.0)
		)
		cannon.runtime_state.enabled = true
		cannon.runtime_state.ammunition = -1
		cannon.reload_left = 0.0
		cannon.aim_at(target)
		cannon.rotation.y = cannon.base_local_yaw_radians
		cannon.call(&"_turn_toward", target, 10.0)
		presentation.refresh_now()
		var ready_preview := _find_preview(presentation, first)
		_check(
			ready_preview != null \
				and ready_preview.line_mesh.material_override \
					== presentation.get_runtime_ready_material(),
			"ready mount uses shared green material"
		)
	first.runtime_state.ammunition = 0
	presentation.refresh_now()
	var blocked_preview := _find_preview(presentation, first)
	_check(
		blocked_preview != null \
			and blocked_preview.line_mesh.material_override \
				== presentation.get_runtime_blocked_material(),
		"no-ammunition mount uses shared blocked material"
	)
	first.runtime_state.ammunition = -1
	first.reload_left = 1.0
	presentation.refresh_now()
	_check(
		blocked_preview.line_mesh.material_override \
			== presentation.get_runtime_blocked_material(),
		"reloading mount remains on shared blocked material"
	)
	var materials_are_shared := true
	for preview in presentation.get_active_previews():
		var material := preview.line_mesh.material_override
		materials_are_shared = materials_are_shared and (
			material == presentation.get_runtime_ready_material() \
			or material == presentation.get_runtime_blocked_material()
		)
	_check(
		materials_are_shared,
		"all previews share only ready or blocked runtime material"
	)
	first.reload_left = 0.0


func _verify_mode_and_pool_reuse(
		battle: BattleScene,
		presentation: ShipWeaponPreviewPresentation,
		cruiser: ShipUnit
) -> void:
	var node_count := presentation.preview_root.get_child_count()
	battle.input_manager.set_command_mode(
		PlayerInputManager.CommandMode.AIRCRAFT
	)
	_check(
		int(presentation.get_debug_snapshot().get(
			"active_preview_count",
			-1
		)) == 0,
		"aircraft mode immediately returns all turret previews"
	)
	battle.input_manager.set_command_mode(
		PlayerInputManager.CommandMode.SHIP
	)
	presentation.refresh_now()
	_check(
		presentation.preview_root.get_child_count() == node_count,
		"ship mode reuses the local preview pool"
	)
	var original_player := battle.player_ship
	battle.input_manager.controlled_ship = original_player
	battle.input_manager.selection_coordinator.select_only(original_player)
	presentation.refresh_now()
	_check(
		presentation.preview_root.get_child_count() == node_count,
		"controlled ship change reuses existing preview scenes"
	)
	battle.input_manager.controlled_ship = cruiser
	battle.input_manager.selection_coordinator.select_only(cruiser)
	presentation.refresh_now()


func _verify_mount_removal(
		presentation: ShipWeaponPreviewPresentation,
		mounts: Array[WeaponMount]
) -> void:
	if mounts.is_empty():
		return
	var previous_count := presentation.get_active_previews().size()
	var removed: WeaponMount = mounts.back()
	removed.queue_free()
	await process_frame
	_check(
		presentation.get_active_previews().size() \
			== previous_count - 1,
		"mount tree exit immediately releases its preview"
	)


func _find_ship(ships: Array[ShipUnit], ship_id: StringName) -> ShipUnit:
	for ship in ships:
		if StringName(ship.ship_id) == ship_id:
			return ship
	return null


func _find_preview(
		presentation: ShipWeaponPreviewPresentation,
		mount: WeaponMount
) -> TurretRangePreview:
	for preview in presentation.get_active_previews():
		if preview.get_bound_mount() == mount:
			return preview
	return null


func _finish(battle: BattleScene) -> void:
	var presentation := battle.ship_weapon_preview_presentation
	battle.shutdown()
	if presentation != null:
		var snapshot := presentation.get_debug_snapshot()
		_check(
			int(snapshot.get("active_preview_count", -1)) == 0 \
				and int(snapshot.get("mount_binding_count", -1)) == 0 \
				and int(snapshot.get("processing_preview_count", -1)) == 0,
			"shutdown clears active previews, signals, and processing"
		)
	battle.queue_free()
	await process_frame
	await process_frame
	for failure in _failures:
		push_error("TURRET PREVIEW LIFECYCLE TEST: %s" % failure)
	print(
		"TURRET_PREVIEW_LIFECYCLE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
