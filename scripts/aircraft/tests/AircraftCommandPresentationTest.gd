extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
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
	battle.aircraft_selection_controller.select_squadron(squadron)
	var presentation := battle.aircraft_command_presentation
	presentation.call(&"_process", 0.2)
	var active_boxes: Dictionary = presentation.get(
		"_active_boxes"
	)
	var box := active_boxes.get(squadron.get_instance_id()) \
		as SquadronSelectionBox
	_check(box != null and box.visible, "selected squadron shows a box")
	if box != null:
		var edges := box.get_children()
		_check(edges.size() == 12, "selection box has twelve edges")
		var shared_mesh: Mesh = (
			edges[0] as MeshInstance3D
		).mesh
		var all_shared := true
		for edge_value in edges:
			var edge := edge_value as MeshInstance3D
			all_shared = all_shared \
				and edge != null \
				and edge.mesh == shared_mesh
		_check(all_shared, "selection edges share one BoxMesh")
	var destination := squadron.formation_center \
		+ Vector3(900.0, 0.0, -600.0)
	_check(
		battle.aircraft_selection_controller.issue_move_command(
			destination
		),
		"selected squadron accepts a player move"
	)
	presentation.call(&"_process", 0.2)
	var snapshot := squadron.get_destination_snapshot()
	_check(
		snapshot.active \
			and snapshot.command_type == &"player_move",
		"path reads the authoritative player destination"
	)
	var active_paths: Dictionary = presentation.get(
		"_active_paths"
	)
	var path := active_paths.get(squadron.get_instance_id()) \
		as SquadronCommandPathPresenter
	_check(path != null and path.visible, "path is visible en route")
	var active_overlays: Dictionary = presentation.get(
		"_active_overlays"
	)
	var overlay := active_overlays.get(squadron.get_instance_id()) \
		as SquadronStatusOverlay
	_check(
		overlay != null \
			and overlay.mouse_filter \
				== Control.MOUSE_FILTER_IGNORE,
		"status overlay does not consume mouse input"
	)
	if overlay != null:
		var state_snapshot := SquadronPresentationSnapshotBuilder \
			.new().build(squadron)
		_check(
			state_snapshot.alive_count \
				<= state_snapshot.total_count \
				and not state_snapshot.weapon_name.is_empty(),
			"status overlay uses a typed squadron snapshot"
		)
	squadron.destination_tracker.mark_reached(
		squadron.destination_tracker.command_serial
	)
	squadron.state = AircraftSquadron.State.HOLDING
	squadron._loiter_initialized = true
	presentation.call(&"_process", 0.2)
	_check(not path.visible, "path hides at destination loiter")
	battle.aircraft_selection_controller.clear_selection()
	_check(not box.visible, "selection box hides when deselected")
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.shutdown()
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("AIRCRAFT COMMAND PRESENTATION TEST: %s" % failure)
	print(
		"AIRCRAFT_COMMAND_PRESENTATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
