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
	var clicked_point := ship.global_position \
		+ Vector3(1200.0, 0.0, -400.0)
	var second_ship := battle.allies[0] \
		if not battle.allies.is_empty() else null
	if second_ship != null:
		battle.input_manager.selection_coordinator.toggle(
			second_ship
		)
	battle.input_manager.ship_command_controller.set_aim_point(
		clicked_point
	)
	var command := ship.combat.get_manual_aim_command()
	_check(command != null, "manual click stores a typed aim command")
	_check(
		ship.combat.aim_mode \
			== ShipCombat.AimMode.MANUAL_RELATIVE_BEARING,
		"player click selects relative-bearing aim mode"
	)
	if second_ship != null:
		var second_command := second_ship.combat \
			.get_manual_aim_command()
		_check(
			second_command != null \
				and not is_equal_approx(
					second_command.local_azimuth_rad,
					command.local_azimuth_rad
				),
			"multiple ships receive independent local bearings"
		)
	var local_direction_before := command.get_local_direction()
	var world_aim_before := ship.combat.aim_point
	ship.global_position += Vector3(500.0, 0.0, 300.0)
	ship.combat.update_weapon_mounts(ship, true)
	var command_after_translation := ship.combat \
		.get_manual_aim_command()
	_check(
		command_after_translation.get_local_direction() \
			.is_equal_approx(local_direction_before),
		"translation preserves local bearing"
	)
	_check(
		not ship.combat.aim_point.is_equal_approx(
			world_aim_before
		),
		"manual aim no longer tracks the clicked world point"
	)
	var world_direction_before := ship.combat \
		.get_manual_aim_world_direction()
	ship.rotate_y(deg_to_rad(45.0))
	ship.combat.update_weapon_mounts(ship, true)
	var world_direction_after := ship.combat \
		.get_manual_aim_world_direction()
	_check(
		world_direction_before.angle_to(world_direction_after) \
			> deg_to_rad(40.0),
		"hull rotation rotates the manual world direction"
	)
	var maximum_range := ship.combat \
		.get_max_weapon_range_m(WeaponTypes.Type.CANNON)
	_check(
		is_equal_approx(
			ship.get_selected_cannon_maximum_range_m(),
			maximum_range
		),
		"aim preview range and cannon runtime range share one source"
	)
	var first_cannon := ship.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)[0]
	var original_range := first_cannon.get_range_m()
	first_cannon.runtime_stats.range_multiplier *= 1.2
	_check(
		ship.get_selected_cannon_maximum_range_m() \
			>= original_range * 1.19,
		"manual preview range includes runtime range upgrades"
	)
	var target := battle.enemies[0] if not battle.enemies.is_empty() \
		else null
	if target != null:
		ship.combat.set_target(target)
		ship.combat.update_weapon_mounts(ship, false)
		_check(
			ship.combat.aim_mode \
				== ShipCombat.AimMode.TRACK_WORLD_TARGET \
				and ship.combat.aim_point.is_equal_approx(
					target.global_position
				),
			"AI world-target tracking remains available"
		)
	battle.shutdown()
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("MANUAL AIM RELATIVE BEARING TEST: %s" % failure)
	print(
		"MANUAL_AIM_RELATIVE_BEARING_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
