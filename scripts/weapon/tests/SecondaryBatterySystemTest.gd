extends SceneTree

var _failures := PackedStringArray()
var _arena: Node3D
var _provider_units: Array = []
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _ship_database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_profile_contract()
	await _test_carrier_mount_classification()
	await _test_main_and_secondary_independence()
	print("SECONDARY_BATTERY_SYSTEM_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _test_profile_contract() -> void:
	var slot := ShipWeaponSlotData.new()
	_check(
		slot.battery_role == BatteryRole.Type.MAIN,
		"existing mount slots default to MAIN"
	)
	var profile := SecondaryBatteryProfile.new()
	_check(profile.validate().is_empty(), "default profile validates")
	profile.scan_interval_sec = 0.0
	profile.target_switch_score_ratio = 0.5
	profile.distance_score_weight = -1.0
	_check(
		profile.validate().size() == 3,
		"profile rejects invalid cadence, hysteresis, and weights"
	)


func _test_carrier_mount_classification() -> void:
	_begin_arena()
	var data := _ship_database.get_ship("cv_seabastion").duplicate(true) \
		as ShipData
	data.secondary_battery_profile = _hold_fire_profile()
	var carrier := _spawn_ship(data, &"player", Vector3.ZERO, true)
	await physics_frame
	_check(
		carrier.combat.get_main_cannon_mounts().is_empty(),
		"carrier secondary slot is excluded from the main battery"
	)
	_check(
		carrier.combat.get_secondary_cannon_mounts().size() == 12,
		"carrier side batteries are classified as twelve SECONDARY mounts"
	)
	_check(
		carrier.get_player_cannon_preview_mounts().is_empty(),
		"automatic secondaries are excluded from player cannon previews"
	)
	var controller := carrier.combat.get_secondary_battery_controller()
	_check(controller != null and controller.is_configured(), "secondary controller is configured")
	if controller != null:
		_check(
			is_equal_approx(controller.get_max_secondary_range_m(), 8000.0),
			"secondary range comes from carrier_secondary WeaponData"
		)
	_end_arena()
	await process_frame


func _test_main_and_secondary_independence() -> void:
	_begin_arena()
	var data := _ship_database.get_ship("dd_bluewind").duplicate(true) \
		as ShipData
	data.secondary_battery_layout = null
	data.secondary_battery_profile = _hold_fire_profile()
	data.weapon_slots[1].battery_role = BatteryRole.Type.SECONDARY
	data.weapon_slots[1].traverse_min_degrees = -180.0
	data.weapon_slots[1].traverse_max_degrees = 180.0
	var player := _spawn_ship(data, &"player", Vector3.ZERO, true)
	var target := _spawn_ship(
		_ship_database.get_ship("dd_bluewind").duplicate(true) as ShipData,
		&"enemy",
		Vector3(0.0, 0.0, -3000.0),
		true
	)
	_provider_units = [player, target]
	player.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	await physics_frame
	# Settle CharacterBody registration before separating the fixture bodies.
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -3000.0)
	player.velocity = Vector3.ZERO
	target.velocity = Vector3.ZERO
	var manual := ShipManualAimCommand.new()
	manual.local_azimuth_rad = 0.35
	manual.range_m = 4200.0
	player.apply_manual_aim_command(manual)
	var original_main_point := player.combat.aim_point
	var controller := player.combat.get_secondary_battery_controller()
	controller.update(0.11)
	_check(
		player.combat.get_main_cannon_mounts().size() == 1 \
			and player.combat.get_secondary_cannon_mounts().size() == 1,
		"mixed battery ship keeps one independent mount in each battery"
	)
	_check(
		controller != null and controller.get_current_target() == target,
		"secondary battery automatically acquires a hostile target"
	)
	_check(
		player.combat.aim_mode == ShipCombat.AimMode.MANUAL_RELATIVE_BEARING \
			and player.combat.aim_source == ShipCombat.AimSource.PLAYER_MANUAL,
		"secondary acquisition does not change player main aim mode"
	)
	_check(
		player.combat.aim_point.distance_to(original_main_point) < 1.0,
		"secondary tracking does not overwrite the main battery aim point"
	)
	_check(
		player.combat.get_ai_fire_control() == null \
			and controller.fire_control != player.combat.get_ai_fire_control(),
		"secondary battery owns a separate fire-control instance"
	)
	var main_mount := player.combat.get_main_cannon_mounts()[0] as CannonMount
	var secondary_mount := player.combat.get_secondary_cannon_mounts()[0]
	_check(
		main_mount.shell_deviation_provider == null \
			and secondary_mount.shell_deviation_provider == controller.fire_control,
		"secondary provider is bound only to SECONDARY mounts"
	)
	_check(
		controller.count_engaging_mounts(target) == 1,
		"target selection uses each secondary mount's range and traverse geometry"
	)
	var better_target := _spawn_ship(
		_ship_database.get_ship("dd_bluewind").duplicate(true) as ShipData,
		&"enemy",
		Vector3(0.0, 0.0, -1000.0),
		true
	)
	player.global_position = Vector3.ZERO
	target.global_position = Vector3(0.0, 0.0, -3000.0)
	better_target.global_position = Vector3(0.0, 0.0, -1000.0)
	_provider_units = [player, target, better_target]
	controller.update(0.11)
	_check(
		controller.get_current_target() == target,
		"better target cannot replace the current target during cooldown"
	)
	controller.update(0.5)
	_check(
		controller.get_current_target() == better_target,
		"better target replaces the current target after cooldown and score ratio"
	)
	better_target.queue_free()
	_provider_units = [player]
	await process_frame
	controller.update(0.31)
	_check(
		controller.get_current_target() == null \
			and secondary_mount.shell_deviation_provider == null,
		"freed target clears secondary tracking and provider safely"
	)
	_end_arena()
	await process_frame


func _hold_fire_profile() -> SecondaryBatteryProfile:
	var profile := SecondaryBatteryProfile.new()
	profile.hold_fire = true
	profile.scan_interval_sec = 0.1
	profile.target_switch_cooldown_sec = 0.5
	profile.target_switch_score_ratio = 1.1
	return profile


func _spawn_ship(
		data: ShipData,
		team: StringName,
		position: Vector3,
		player_controlled: bool
) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	ship.setup(data, team, player_controlled, Color.WHITE)
	_arena.add_child(ship)
	ship.global_position = position
	return ship


func _get_provider_units() -> Array:
	var result: Array = []
	for value: Variant in _provider_units:
		if value != null and is_instance_valid(value):
			result.append(value)
	return result


func _begin_arena() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)


func _end_arena() -> void:
	_provider_units.clear()
	if _arena != null:
		_arena.queue_free()
		_arena = null


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("SECONDARY BATTERY SYSTEM: %s" % description)
