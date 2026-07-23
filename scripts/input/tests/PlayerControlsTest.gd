extends SceneTree

var _failures: Array[String] = []
var _captured_player_projectile: Projectile

func _initialize() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_expect(packed != null, "battle scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as BattleScene
	root.add_child(scene)
	await process_frame
	await physics_frame

	_expect(_action_has_key(&"ship_throttle_forward", KEY_W), "W raises engine output")
	_expect(_action_has_key(&"ship_throttle_reverse", KEY_S), "S lowers engine output")
	_expect(_action_has_key(&"ship_rudder_left", KEY_A), "A commands left rudder")
	_expect(_action_has_key(&"ship_rudder_right", KEY_D), "D commands right rudder")
	_expect(_action_has_key(&"ship_fire", KEY_CTRL), "Ctrl fires guns")
	_expect(_action_has_key(&"camera_move_forward", KEY_UP), "camera keyboard movement uses arrow keys")
	_expect(_action_has_mouse_button(&"camera_zoom_in", MOUSE_BUTTON_WHEEL_UP), "wheel up zoom is mapped")
	_expect(_action_has_mouse_button(&"camera_zoom_out", MOUSE_BUTTON_WHEEL_DOWN), "wheel down zoom is mapped")

	var player := scene.player_ship as ShipUnit
	var range_renderer := scene.ballistic_trajectory_renderer as BallisticTrajectoryRenderer
	range_renderer.call(&"_redraw")
	_expect(range_renderer.has_visible_range_line(), "maximum range line is visible before a click target is assigned")
	_expect(is_equal_approx(range_renderer.get_rendered_maximum_range_m(), 12000.0), "destroyer maximum range line uses 12 km weapon data")
	var range_mesh := range_renderer.mesh_instance.mesh as ImmediateMesh
	var range_material := range_mesh.surface_get_material(0) as StandardMaterial3D if range_mesh.get_surface_count() > 0 else null
	_expect(
		range_material != null and range_material.albedo_color.is_equal_approx(Color.WHITE),
		"maximum range line uses a simple white material"
	)
	var range_vertices := range_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var primary_range_turret := player.get_turrets()[0] as Turret
	var range_origin := primary_range_turret.get_muzzle_position()
	var range_direction := -primary_range_turret.global_transform.basis.z
	range_direction.y = 0.0
	range_direction = range_direction.normalized()
	var maximum_projection_m := 0.0
	for vertex in range_vertices:
		maximum_projection_m = maxf(maximum_projection_m, (vertex - range_origin).dot(range_direction))
	_expect(
		range_vertices.size() > 60 and absf(maximum_projection_m - 12000.0) < 1.0,
		"white dotted line repeats to the full maximum range"
	)
	Input.action_press(&"ship_throttle_forward")
	for _frame in 30:
		await physics_frame
	Input.action_release(&"ship_throttle_forward")
	var raised_output := player.get_engine_output()
	_expect(raised_output > 0.1, "holding W increases engine output")

	Input.action_press(&"ship_throttle_reverse")
	for _frame in 15:
		await physics_frame
	Input.action_release(&"ship_throttle_reverse")
	_expect(player.get_engine_output() < raised_output, "holding S decreases engine output")

	var yaw_before := player.global_rotation.y
	Input.action_press(&"ship_rudder_left")
	for _frame in 30:
		await physics_frame
	Input.action_release(&"ship_rudder_left")
	_expect(absf(angle_difference(yaw_before, player.global_rotation.y)) > deg_to_rad(0.01), "A changes hull yaw gradually")

	var aim_target := player.global_position + Vector3(3200.0, 0.0, -800.0)
	var screen_position := scene.camera.unproject_position(aim_target)
	scene.input_manager.call(&"_handle_primary_click", screen_position)
	var applied_aim: Variant = player.get_current_aim_point()
	_expect(applied_aim is Vector3 and Vector2(applied_aim.x - aim_target.x, applied_aim.z - aim_target.z).length() < 2.0, "left click sets the sea-plane aim point")
	var turrets := player.get_turrets()
	var primary_turret := turrets[0] as Turret if not turrets.is_empty() else null
	var calculated_pitch: Variant = primary_turret.calculate_ballistic_pitch_deg(applied_aim) if primary_turret != null else null
	_expect(
		primary_turret != null and calculated_pitch != null \
			and absf(primary_turret.get_target_pitch_degrees() - float(calculated_pitch)) < 0.01,
		"left click immediately sets the calculated target gun elevation"
	)
	_expect(
		primary_turret != null and primary_turret.ballistic_gravity_multiplier >= 4.0,
		"visible naval arc uses the same enhanced gravity for aiming and projectiles"
	)
	for _frame in 90:
		await physics_frame
	await process_frame

	_expect(not turrets.is_empty() and absf(turrets[0].pitch_degrees - 18.0) > 0.1, "aim point automatically adjusts gun elevation")
	_expect(
		primary_turret != null and absf(primary_turret.pitch_degrees - primary_turret.get_target_pitch_degrees()) < 0.15,
		"gun barrel converges to the calculated elevation"
	)
	_expect(scene.aim_target_marker.visible, "requested aim marker is visible")
	_expect(scene.impact_marker.visible, "predicted impact marker is visible")
	var predicted_impact: Variant = player.get_primary_impact_point(scene.gravity)
	_expect(
		predicted_impact is Vector3 and Vector2(
			predicted_impact.x - applied_aim.x,
			predicted_impact.z - applied_aim.z
		).length() < 80.0,
		"converged gun elevation lands within 80 m of the clicked point"
	)
	_expect(scene.ballistic_trajectory_renderer.has_visible_trajectory(), "full ballistic range line is visible")
	var impact_torus := scene.impact_marker.mesh as TorusMesh
	_expect(impact_torus != null and impact_torus.outer_radius >= 30.0, "predicted impact marker remains visible at RTS height")
	_expect("Aim range" in scene.hud.status_label.text and "Expected impact" in scene.hud.status_label.text, "HUD displays range and expected impact coordinates")

	var event_bus := root.get_node_or_null("EventBus")
	if event_bus != null and not event_bus.projectile_fired.is_connected(_on_projectile_fired):
		event_bus.projectile_fired.connect(_on_projectile_fired)
	Input.action_press(&"ship_fire")
	for _frame in 3:
		await physics_frame
	Input.action_release(&"ship_fire")
	var fired := false
	for turret in turrets:
		if turret.reload_left > 0.0:
			fired = true
			break
	_expect(fired, "Ctrl fires the player ship guns")
	_expect(
		_captured_player_projectile != null \
			and is_equal_approx(_captured_player_projectile.gravity_scale, primary_turret.ballistic_gravity_multiplier),
		"fired projectile uses the same enhanced gravity as the gun elevation solver"
	)
	_expect(
		_captured_player_projectile != null and _captured_player_projectile.firing_body == player,
		"projectile ignores its firing ship while leaving the gun muzzle"
	)

	print("PLAYER_CONTROLS checks=28 failures=%d" % _failures.size())
	for failure in _failures:
		push_error("PLAYER CONTROLS TEST: %s" % failure)
	scene.queue_free()
	await process_frame
	await physics_frame
	_finish()

func _action_has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _on_projectile_fired(projectile: Projectile) -> void:
	if projectile != null and projectile.team == &"player":
		_captured_player_projectile = projectile

func _action_has_mouse_button(action: StringName, button_index: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button_index:
			return true
	return false

func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

func _finish() -> void:
	quit(0 if _failures.is_empty() else 1)
