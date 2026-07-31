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
	var ship := battle.player_ship
	var cannons := ship.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)
	_check(not cannons.is_empty(), "player ship has cannon mounts")
	if cannons.is_empty():
		await _finish(battle)
		return
	var expected_range := 0.0
	for mount in cannons:
		if mount.is_operational():
			expected_range = maxf(
				expected_range,
				mount.get_runtime_maximum_range_m()
			)
	_check(
		is_equal_approx(
			ship.get_player_cannon_preview_range_m(),
			expected_range
		),
		"preview reads operational runtime cannon range"
	)
	var enabled_states: Array[bool] = []
	for mount in cannons:
		enabled_states.append(mount.runtime_state.enabled)
		mount.runtime_state.enabled = false
	_check(
		is_zero_approx(ship.get_player_cannon_preview_range_m()),
		"disabled cannon mounts are excluded"
	)
	for index in cannons.size():
		cannons[index].runtime_state.enabled = enabled_states[index]
	var preview := battle.ship_aim_range_preview
	var material_before := preview.get_runtime_material()
	preview.show_preview(
		ship.get_player_cannon_preview_origin(),
		-ship.global_basis.z,
		ship.get_player_cannon_preview_range_m()
	)
	preview.show_preview(
		ship.get_player_cannon_preview_origin(),
		ship.global_basis.x,
		ship.get_player_cannon_preview_range_m()
	)
	_check(
		material_before != null \
			and material_before == preview.get_runtime_material(),
		"aim preview reuses one runtime material"
	)
	_verify_mount_rest_contract(ship)
	await _finish(battle)


func _verify_mount_rest_contract(ship: ShipUnit) -> void:
	var mount := WeaponMount.new()
	mount.rotation.y = deg_to_rad(45.0)
	ship.add_child(mount)
	var slot := ShipWeaponSlotData.new()
	slot.traverse_min_degrees = -10.0
	slot.traverse_max_degrees = 10.0
	mount.setup(null, slot, ship, ship.team, ship.battle_services)
	var hull_forward_point := ship.global_position \
		- ship.global_basis.z * 1000.0
	var target_yaw: Variant = mount \
		.get_target_local_yaw_for_world_point(hull_forward_point)
	_check(
		target_yaw != null \
			and is_equal_approx(
				float(target_yaw),
				deg_to_rad(35.0)
			),
		"limited traverse clamps hull bearing relative to mount rest yaw"
	)
	_check(
		is_equal_approx(
			mount.get_rest_yaw_relative_to_hull(),
			deg_to_rad(45.0)
		),
		"mount exposes its initial rest yaw"
	)
	mount.queue_free()


func _finish(battle: BattleScene) -> void:
	battle.shutdown()
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("WEAPON PREVIEW CONTRACT TEST: %s" % failure)
	print(
		"WEAPON_PREVIEW_CONTRACT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
