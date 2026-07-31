extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const BOX_SCENE := preload(
	"res://scenes/aircraft/presentation/SquadronSelectionBox.tscn"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await process_frame
	var squadron := battle.player_ship.carrier_air_group \
		.launch_manual_squadron("basic_bomber_squadron")
	_check(squadron != null, "test squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	battle.input_manager.set_command_mode(
		PlayerInputManager.CommandMode.AIRCRAFT
	)
	var presentation := battle.aircraft_command_presentation
	battle.aircraft_selection_controller.select_squadron(squadron)
	presentation.call(&"_process", 0.2)
	var squadron_id := squadron.get_instance_id()
	var box := (
		presentation.get("_active_boxes") as Dictionary
	).get(squadron_id) as SquadronSelectionBox
	var path := (
		presentation.get("_active_paths") as Dictionary
	).get(squadron_id) as SquadronCommandPathPresenter
	var overlay := (
		presentation.get("_active_overlays") as Dictionary
	).get(squadron_id) as SquadronStatusOverlay
	_check(box != null and path != null and overlay != null,
		"selection acquires all three presenters")
	_verify_material_contract(box, path)
	_verify_overlay_projection(battle.camera, overlay)
	_verify_bounds_smoothing(box)
	var initial_connections := squadron.player_destination_changed \
		.get_connections().size()
	battle.aircraft_selection_controller.clear_selection()
	var released := presentation.get_debug_snapshot()
	_check(
		int(released["active_selection_box_count"]) == 0 \
			and int(released["active_path_count"]) == 0 \
			and int(released["active_overlay_count"]) == 0 \
			and int(released["active_binding_count"]) == 0,
		"deselect deactivates presenters and signal binding"
	)
	_check(
		int(released["processing_presenter_count"]) == 0,
		"pooled presenters do not process"
	)
	battle.aircraft_selection_controller.select_squadron(squadron)
	presentation.call(&"_process", 0.2)
	_check(
		squadron.player_destination_changed.get_connections().size() \
			== initial_connections,
		"reselect does not duplicate destination callbacks"
	)
	var destination := squadron.formation_center \
		+ Vector3(900.0, 0.0, -500.0)
	battle.aircraft_selection_controller.issue_move_command(destination)
	var active_path := (
		presentation.get("_active_paths") as Dictionary
	).get(squadron_id) as SquadronCommandPathPresenter
	_check(active_path != null and active_path.visible,
		"destination signal shows path immediately")
	var destination_snapshot := squadron.get_destination_snapshot()
	if active_path != null:
		_check(
			is_equal_approx(
				active_path.destination_marker.global_position.y,
				destination_snapshot.command_plane_height_m \
					+ presentation.settings.path_height_offset_m
			) and is_equal_approx(
				active_path.path_line.global_position.y,
				destination_snapshot.command_plane_height_m \
					+ presentation.settings.path_height_offset_m
			),
			"path and marker share the command-plane height"
		)
	squadron.destination_tracker.mark_reached(
		squadron.destination_tracker.command_serial
	)
	squadron.state = AircraftSquadron.State.HOLDING
	squadron._loiter_initialized = true
	squadron._on_destination_command_reached()
	_check(not active_path.visible,
		"destination-reached signal hides path without polling")
	squadron.request_return()
	var returned := presentation.get_debug_snapshot()
	_check(
		int(returned["active_selection_box_count"]) == 0 \
			and int(returned["active_binding_count"]) == 0,
		"return releases presentation immediately"
	)
	await _finish(battle)


func _verify_material_contract(
		box: SquadronSelectionBox,
		path: SquadronCommandPathPresenter
) -> void:
	if box == null or path == null:
		return
	var runtime_material := box.get_runtime_material()
	var all_shared := runtime_material != null
	for child in box.get_children():
		var edge := child as MeshInstance3D
		all_shared = all_shared \
			and edge != null \
			and edge.material_override == runtime_material
	var untouched := BOX_SCENE.instantiate() as SquadronSelectionBox
	var source_edge := untouched.get_child(0) as MeshInstance3D
	_check(
		all_shared \
			and source_edge.material_override != runtime_material,
		"one runtime material is shared without mutating scene material"
	)
	untouched.free()
	_check(
		path.get_runtime_material() != null \
			and path.path_line.material_override \
				== path.destination_marker.material_override,
		"path line and marker share one runtime material"
	)


func _verify_overlay_projection(
		camera: Camera3D,
		overlay: SquadronStatusOverlay
) -> void:
	if camera == null or overlay == null:
		return
	var front_center := camera.global_position \
		- camera.global_basis.z * 1000.0
	var front_bounds := AABB(
		front_center - Vector3(50.0, 30.0, 50.0),
		Vector3(100.0, 60.0, 100.0)
	)
	var screen_bounds := SquadronStatusOverlay.get_screen_bounds(
		camera,
		front_bounds
	)
	_check(screen_bounds.size.x > 0.0 and screen_bounds.size.y > 0.0,
		"all visible AABB corners produce screen bounds")
	overlay.set_screen_bounds(camera, front_bounds, Vector2(8.0, 8.0))
	var viewport_size := camera.get_viewport().get_visible_rect().size
	_check(
		overlay.visible \
			and overlay.position.x >= 0.0 \
			and overlay.position.y >= 0.0 \
			and overlay.position.x + overlay.size.x \
				<= viewport_size.x + 0.01 \
			and overlay.position.y + overlay.size.y \
				<= viewport_size.y + 0.01,
		"overlay is clamped inside the viewport"
	)
	var behind_center := camera.global_position \
		+ camera.global_basis.z * 1000.0
	overlay.set_screen_bounds(
		camera,
		AABB(
			behind_center - Vector3(20.0, 20.0, 20.0),
			Vector3(40.0, 40.0, 40.0)
		),
		Vector2.ZERO
	)
	_check(not overlay.visible, "overlay hides when all corners are behind")


func _verify_bounds_smoothing(box: SquadronSelectionBox) -> void:
	if box == null:
		return
	box.set_bounds(AABB(Vector3.ZERO, Vector3(100.0, 50.0, 100.0)), 0.08)
	box.set_bounds(AABB(Vector3.ZERO, Vector3(220.0, 80.0, 220.0)), 0.08)
	_check(box.get_display_size().x >= 220.0,
		"selection bounds expand immediately")
	box.set_bounds(AABB(Vector3.ZERO, Vector3(100.0, 50.0, 100.0)), 0.08)
	_check(
		box.get_display_size().x > 100.0 \
			and box.get_display_size().x < 220.0,
		"selection bounds shrink smoothly"
	)


func _finish(battle: BattleScene) -> void:
	battle.shutdown()
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("AIRCRAFT PRESENTATION STABILITY TEST: %s" % failure)
	print(
		"AIRCRAFT_PRESENTATION_STABILITY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
