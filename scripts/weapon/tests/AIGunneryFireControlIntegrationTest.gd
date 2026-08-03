extends SceneTree
## Integration: an AI ship engaging a moving target leads ahead of its travel
## direction, imperfectly (never a perfect solution); weapon groups with
## different shell speeds compute different leads; player manual aim never
## routes through the AI fire-control or its difficulty error.

var _failures := PackedStringArray()
var _arena: Node3D
var _provider_units: Array = []
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _ship_database := ShipDatabase.new()
var _weapon_database := WeaponDatabase.new()
var _mount_scene := preload("res://scenes/weapon/mounts/cannon_mount.tscn")


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_ai_leads_moving_target()
	await _test_weapon_groups_use_different_leads()
	await _test_player_manual_aim_unaffected()
	await _test_freed_target_does_not_crash()
	print(
		"AI_GUNNERY_FIRE_CONTROL_INTEGRATION_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


## Regression: a target destroyed mid-engagement leaves ShipCombat holding a
## freed reference for at least one frame. Casting it before validating it
## raised "Trying to cast a freed object" every physics frame.
##
## Note on the assertion: a failed cast still yields null, so the _check calls
## below pass with or without the guard. The actual regression signal is the
## engine error on stderr -- this case must run with a stderr free of
## "Trying to cast a freed object" (5 occurrences before the fix, 0 after).
func _test_freed_target_does_not_crash() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var hunter := _spawn_ship("dd_bluewind", &"enemy", Vector3.ZERO, false)
	var victim := _spawn_ship(
		"dd_bluewind", &"ally", Vector3(0, 0, 3000), false
	)
	await physics_frame
	hunter.combat.set_ai_engagement_target(victim)
	for _frame in 3:
		await physics_frame
	_check(
		hunter.combat.get_ai_fire_control() != null,
		"freed target: fire control is active before the target dies"
	)
	# Free the target WITHOUT going through clear_target(), reproducing the
	# window where targeting has not yet notified the combat component.
	victim.free()
	_check(
		hunter.combat._get_ai_fire_control_target() == null,
		"freed target: resolver reports no target instead of casting"
	)
	for _frame in 3:
		await physics_frame
	var cannons := hunter.combat.get_weapons_by_type(WeaponTypes.Type.CANNON)
	var providers_released := true
	for cannon in cannons:
		if (cannon as CannonMount).shell_deviation_provider != null:
			providers_released = false
	_check(
		providers_released,
		"freed target: AI dispersion providers are released"
	)
	_check(
		is_instance_valid(hunter),
		"freed target: the shooter keeps running after the target is freed"
	)
	_cleanup_arena()
	await process_frame


func _test_ai_leads_moving_target() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var hunter := _spawn_ship("dd_bluewind", &"enemy", Vector3.ZERO, false)
	var target := _spawn_ship(
		"dd_bluewind", &"ally", Vector3(0, 0, 4000), true
	)
	_provider_units = [hunter, target]
	hunter.configure_ai_target_provider(
		Callable(self, &"_get_provider_units")
	)
	target.set_player_commands(1.0, 0.0, false)
	for _frame in 150:
		await physics_frame
	var target_velocity := target.get_world_velocity()
	_check(
		target_velocity.length() > 2.0,
		"integration: target ship is actually moving (%.1f m/s)"
			% target_velocity.length()
	)
	_check(
		hunter.combat.aim_source == ShipCombat.AimSource.AI,
		"integration: AI engagement runs with AimSource.AI"
	)
	var cannons := hunter.combat.get_weapons_by_type(WeaponTypes.Type.CANNON)
	_check(not cannons.is_empty(), "integration: hunter has cannon mounts")
	if cannons.is_empty():
		_cleanup_arena()
		return
	var aim_point: Vector3 = cannons[0].aim_point
	var aim_offset := aim_point - target.global_position
	aim_offset.y = 0.0
	_check(
		aim_offset.length() > 5.0,
		"integration: AI does not aim at the target's current position"
	)
	var travel_direction := target_velocity
	travel_direction.y = 0.0
	if travel_direction.length_squared() > 0.01:
		_check(
			aim_offset.normalized().dot(travel_direction.normalized()) > 0.15,
			"integration: aim leads toward the travel direction"
		)
	var fire_control := hunter.combat.get_ai_fire_control()
	_check(
		fire_control != null,
		"integration: AI combat owns a fire control instance"
	)
	if fire_control != null:
		var snapshots := fire_control.get_debug_snapshots()
		_check(
			not snapshots.is_empty()
				and snapshots[0].projectile_flight_time_sec > 0.0,
			"integration: solution reports a positive shell flight time"
		)
		var perfect := true
		for snapshot in snapshots:
			if not snapshot.actual_aim_point.is_equal_approx(
				snapshot.ideal_aim_point
			):
				perfect = false
		_check(
			not perfect,
			"integration: accuracy error keeps the AI from a perfect solution"
		)
	_check(
		(cannons[0] as CannonMount).shell_deviation_provider != null,
		"integration: cannons receive the per-shell dispersion provider"
	)
	_cleanup_arena()


func _test_weapon_groups_use_different_leads() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var shooter := _spawn_ship("dd_bluewind", &"enemy", Vector3.ZERO, false)
	var target := _spawn_ship(
		"dd_bluewind", &"ally", Vector3(0, 0, 5000), false
	)
	target.velocity = Vector3(14.0, 0.0, 0.0)
	var fast_mount := _spawn_mount("battleship_cannon", Vector3(0, 2, 6))
	var slow_mount := _spawn_mount("destroyer_cannon", Vector3(0, 2, -6))
	await physics_frame
	var fast_speed: float = fast_mount.get_modified_projectile_speed(
		fast_mount.muzzle_velocity
	)
	var slow_speed: float = slow_mount.get_modified_projectile_speed(
		slow_mount.muzzle_velocity
	)
	if is_equal_approx(fast_speed, slow_speed):
		_check(false, "groups: test weapons must differ in muzzle velocity")
		_cleanup_arena()
		return
	var mounts: Array[WeaponMount] = [fast_mount, slow_mount]
	var fire_control := ShipGunneryFireControl.new()
	fire_control.configure(
		preload("res://resources/ai_difficulty/gunnery_normal.tres"),
		GunneryCrewStats.new(),
		null
	)
	fire_control.update(shooter, target, mounts)
	var fast_point := fire_control.get_aim_point_for_mount(
		fast_mount, target.global_position
	)
	var slow_point := fire_control.get_aim_point_for_mount(
		slow_mount, target.global_position
	)
	_check(
		fire_control.has_solution_for_mount(fast_mount)
			and fire_control.has_solution_for_mount(slow_mount),
		"groups: both weapon groups solve"
	)
	_check(
		not fast_point.is_equal_approx(slow_point),
		"groups: different shell speeds produce different aim solutions"
	)
	var snapshots := fire_control.get_debug_snapshots()
	var flight_times: Dictionary = {}
	for snapshot in snapshots:
		flight_times[snapshot.weapon_group_id] = \
			snapshot.projectile_flight_time_sec
	_check(
		flight_times.size() == 2,
		"groups: one solution per weapon group"
	)
	_cleanup_arena()


func _test_player_manual_aim_unaffected() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var player := _spawn_ship("dd_bluewind", &"player", Vector3.ZERO, true)
	await physics_frame
	var manual_command := ShipManualAimCommand.new()
	manual_command.local_azimuth_rad = 0.35
	manual_command.elevation_rad = 0.1
	manual_command.range_m = 3000.0
	player.apply_manual_aim_command(manual_command)
	for _frame in 5:
		await physics_frame
	_check(
		player.combat.aim_source == ShipCombat.AimSource.PLAYER_MANUAL,
		"player: manual aim keeps AimSource.PLAYER_MANUAL"
	)
	_check(
		player.combat.get_ai_fire_control() == null,
		"player: no AI fire control is created for manual aim"
	)
	var expected_direction := player.combat.get_manual_aim_world_direction()
	var expected_point: Vector3 = player.global_position \
		+ expected_direction * 3000.0
	_check(
		player.combat.aim_point.distance_to(expected_point) < 1.0,
		"player: aim point is exactly the manual bearing point"
	)
	var cannons := player.combat.get_weapons_by_type(WeaponTypes.Type.CANNON)
	var providers_clear := true
	for cannon in cannons:
		if (cannon as CannonMount).shell_deviation_provider != null:
			providers_clear = false
	_check(
		providers_clear,
		"player: cannons carry no AI dispersion provider"
	)
	_cleanup_arena()


func _cleanup_arena() -> void:
	_provider_units.clear()
	if _arena != null:
		_arena.queue_free()
		_arena = null


func _get_provider_units() -> Array:
	var valid_units: Array = []
	for ship in _provider_units:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			valid_units.append(ship)
	return valid_units


func _spawn_ship(
		ship_id: String,
		team: StringName,
		position: Vector3,
		is_player: bool
) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	var source_data := _ship_database.get_ship(ship_id)
	ship.setup(
		source_data.duplicate(true) as ShipData,
		team,
		is_player,
		Color.WHITE
	)
	_arena.add_child(ship)
	ship.global_position = position
	return ship


func _spawn_mount(weapon_id: String, position: Vector3) -> CannonMount:
	var mount := _mount_scene.instantiate() as CannonMount
	_arena.add_child(mount)
	mount.setup(
		_weapon_database.get_weapon(weapon_id),
		null,
		null,
		&"enemy"
	)
	mount.global_position = position
	return mount


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("AI GUNNERY INTEGRATION: %s" % label)
