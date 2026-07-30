extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_check(packed != null, "battle scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as BattleScene
	var test_config := BattleTestConfig.new()
	test_config.enabled = true
	test_config.player_ship_override = &"bb_ironwake"
	scene.test_config = test_config
	root.add_child(scene)
	await process_frame
	await physics_frame

	var settings := scene.battlefield_settings
	var bounds := scene.battlefield_bounds
	_check(settings.map_size_m == Vector2(20000.0, 20000.0), "map is 20 km x 20 km")
	_check(bounds.is_inside_bounds(Vector3(10000.0, 500.0, -10000.0)), "boundary includes exact corners and ignores Y")
	_check(not bounds.is_inside_bounds(Vector3(10000.1, 0.0, 0.0)), "outside point is rejected")
	var clamped := bounds.clamp_to_bounds(Vector3(15000.0, 7.0, -14000.0), 250.0)
	_check(clamped.is_equal_approx(Vector3(9750.0, 7.0, -9750.0)), "outside target clamps to margin")
	_check(is_equal_approx(bounds.get_distance_to_boundary(Vector3.ZERO), 10000.0), "center boundary distance is 10 km")

	var player := scene.player_ship as ShipUnit
	var original_position := player.global_position
	player.set_aim_point(original_position + Vector3(5000.0, 0.0, 0.0))
	for _frame in 90:
		await physics_frame
	var long_range_impact: Variant = player.get_primary_impact_point(scene.gravity)
	_check(long_range_impact != null, "5 km ballistic solution produces an impact point")
	if long_range_impact != null:
		var impact_range_m := Vector2(
			long_range_impact.x - player.global_position.x,
			long_range_impact.z - player.global_position.z
		).length()
		_check(impact_range_m >= 4700.0 and impact_range_m <= 5300.0, "automatic gun pitch matches a 5 km aim point")
	player.set_aim_point(original_position + Vector3(12000.0, 0.0, 0.0))
	for _frame in 90:
		await physics_frame
	var maximum_test_impact: Variant = player.get_primary_impact_point(scene.gravity)
	_check(maximum_test_impact != null, "12 km ballistic solution produces an impact point")
	if maximum_test_impact != null:
		var maximum_impact_range_m := Vector2(
			maximum_test_impact.x - player.global_position.x,
			maximum_test_impact.z - player.global_position.z
		).length()
		_check(
			maximum_impact_range_m >= 11400.0 \
				and maximum_impact_range_m <= 12600.0,
			"automatic gun pitch matches a 12 km aim point "
				+ "(actual=%.2f)" % maximum_impact_range_m
		)
	player.global_position = Vector3(10300.0, 0.0, 0.0)
	player.clear_navigation_target()
	player.navigation.update_navigation(0.1)
	_check(player.navigation.has_navigation_target, "an outside ship receives a return route")
	_check(player.global_position.is_equal_approx(Vector3(10300.0, 0.0, 0.0)), "boundary recovery does not teleport an outside ship")
	player.global_position = original_position
	player.clear_navigation_target()
	player.set_navigation_target(Vector3(15000.0, 200.0, -15000.0))
	_check(player.global_position.is_equal_approx(original_position), "navigation never teleports the ship")
	_check(player.navigation.target_position.is_equal_approx(Vector3(9750.0, 0.0, -9750.0)), "navigation normalizes sea level and bounds")
	_check(player.navigation.has_valid_path(), "open-ocean route is available")

	player.set_navigation_target(original_position + Vector3(5000.0, 0.0, 0.0))
	var path_before := player.navigation.current_path
	for _frame in 120:
		await physics_frame
	_check(player.movement.get_speed() > 0.1, "ship accelerates toward a 5 km target")
	_check(player.global_position.distance_to(original_position) > 0.1, "movement controller advances the ship")
	_check(path_before.size() == player.navigation.current_path.size(), "route does not rebuild every physics frame")

	player.clear_navigation_target()
	player.set_physics_process(false)
	player.global_position = Vector3.ZERO
	player.global_rotation = Vector3.ZERO
	player.movement.current_speed_mps = 18.0
	player.movement.current_turn_rate_rad_sec = 0.0
	player.set_navigation_target(Vector3(0.0, 0.0, 5000.0))
	var start_yaw := player.global_rotation.y
	player.set_physics_process(true)
	for _frame in 60:
		await physics_frame
	var yaw_change := absf(angle_difference(start_yaw, player.global_rotation.y))
	_check(yaw_change > deg_to_rad(0.05), "rear waypoint produces gradual steering")
	_check(yaw_change < deg_to_rad(12.0), "rear waypoint cannot instant-turn the hull")

	var ships: Array = [player]
	ships.append_array(scene.allies)
	ships.append_array(scene.enemies)
	var ship_scene := load("res://scenes/unit/ship.tscn") as PackedScene
	var database := ShipDatabase.new()
	for index in 4:
		var extra := ship_scene.instantiate() as ShipUnit
		extra.setup(database.get_ship("dd_bluewind"), &"ally", false, Color(0.2, 0.7, 0.9))
		scene.ships_root.add_child(extra)
		extra.global_position = Vector3(-1800.0 + index * 400.0, 0.0, 800.0)
		ships.append(extra)
	for index in ships.size():
		var destination := Vector3(3500.0 + (index % 4) * 320.0, 0.0, 2500.0 + (index / 4) * 320.0)
		ships[index].set_navigation_target(destination)
	var valid_route_count := 0
	var schedule_offsets: Dictionary = {}
	for ship in ships:
		if ship.navigation.has_valid_path():
			valid_route_count += 1
		schedule_offsets[snappedf(ship.navigation.path_recalculation_elapsed_sec, 0.001)] = true
	_check(ships.size() == 10 and valid_route_count == 10, "10 ships receive valid routes")
	_check(schedule_offsets.size() > 1, "periodic route schedules are staggered")

	var avoidance_owner := ships[6] as ShipUnit
	var avoidance_other := ships[7] as ShipUnit
	avoidance_owner.set_physics_process(false)
	avoidance_other.set_physics_process(false)
	avoidance_owner.global_position = Vector3(0.0, 0.0, 0.0)
	avoidance_other.global_position = Vector3(0.0, 0.0, -300.0)
	avoidance_owner.velocity = Vector3(0.0, 0.0, -20.0)
	avoidance_other.velocity = Vector3(0.0, 0.0, 20.0)
	await physics_frame
	avoidance_owner.avoidance.call(&"_evaluate_nearby_ships")
	_check(avoidance_owner.avoidance.has_collision_risk(), "predictive avoidance detects a closing ship")
	_check(absf(avoidance_owner.avoidance.steering_offset) > 0.0, "avoidance generates a stable rudder offset")
	_check(avoidance_owner.avoidance.speed_scale < 1.0, "collision risk reduces requested speed")

	var camera := scene.camera as RTSCamera
	var fast_crossing_time_sec := settings.map_size_m.x / (settings.camera_max_move_speed_mps * camera.fast_move_multiplier)
	_check(fast_crossing_time_sec >= 8.0 and fast_crossing_time_sec <= 15.0, "fast camera crosses the map in 8-15 seconds")
	camera.adjust_zoom(100.0)
	_check(is_equal_approx(camera.target_height_m, settings.camera_min_height_m), "camera minimum zoom clamps")
	camera.adjust_zoom(-200.0)
	_check(is_equal_approx(camera.target_height_m, settings.camera_max_height_m), "camera maximum zoom clamps")
	camera.focus_on_nodes([ships[0], ships[1], ships[2]])
	for _frame in 30:
		await process_frame
	_check(camera.focus_position.length() < 11000.0, "fleet focus remains in battlefield camera bounds")
	camera.focus_position = Vector3(50000.0, 0.0, -50000.0)
	camera.call(&"_clamp_focus_position")
	_check(absf(camera.focus_position.x) <= 10500.0 and absf(camera.focus_position.z) <= 10500.0, "camera center obeys padded map bounds")

	var ocean_visual := scene.get_node("Ocean/OceanVisual") as OceanVisual
	_check(is_zero_approx(ocean_visual.get_wave_height_at_world_position(Vector3(9000.0, 0.0, 9000.0))), "disabled wave displacement remains disabled at distant coordinates")
	_check(ocean_visual.mesh_size >= 48000.0 and ocean_visual.mesh_subdivisions == 64, "ocean uses a low-density camera-following mesh")
	_check(camera.far >= 30000.0 and camera.near >= 0.5, "camera clipping supports the 20 km world")
	_check(not InputMap.action_get_events(&"camera_move_forward").is_empty(), "camera controls use populated InputMap actions")
	var debug_renderer := scene.get_node("NavigationDebugRenderer") as NavigationDebugRenderer
	debug_renderer.call(&"_redraw")
	debug_renderer.call(&"_update_debug_label")
	_check(debug_renderer.get_child(0).mesh.get_surface_count() == 1, "debug data renders in one ImmediateMesh surface")

	print("BATTLEFIELD expansion checks=%d failures=%d" % [34, _failures.size()])
	for failure in _failures:
		push_error("BATTLEFIELD TEST: %s" % failure)
	scene.queue_free()
	await process_frame
	_finish()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

func _finish() -> void:
	quit(0 if _failures.is_empty() else 1)
