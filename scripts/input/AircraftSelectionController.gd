extends Node
class_name AircraftSelectionController

signal selection_changed(squadrons: Array[AircraftSquadron])
signal command_feedback(message: String)

enum SelectionBlockReason {
	NONE,
	INVALID,
	QUEUED_FOR_DELETION,
	RETURNING,
	RECOVERING,
	DESTROYED,
	NO_AIRCRAFT,
	NO_CARRIER,
	CARRIER_NOT_PLAYER_CONTROLLED,
	WRONG_TEAM,
}

@export var minimum_drag_distance_pixels := 8.0
@export var click_selection_radius_pixels := 18.0
@export var squadron_command_spacing_m := 150.0
@export var battlefield_boundary_margin_m := 250.0
@export var debug_selection := false

var selected_squadrons: Array[AircraftSquadron] = []
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
var _dragging := false

var _camera: RTSCamera
var _selection_rect: Control
var _battlefield_bounds: BattlefieldBounds
var _water_height_m := 0.0
var _last_right_click_position := Vector3.ZERO
var _last_input_consumer := ""
var _input_enabled := true
var _last_candidate_count := 0


func _ready() -> void:
	if has_node("/root/EventBus"):
		var event_bus := get_node("/root/EventBus")
		if not event_bus.battle_cleared.is_connected(_on_battle_ended):
			event_bus.battle_cleared.connect(_on_battle_ended)
		if not event_bus.battle_failed.is_connected(_on_battle_ended):
			event_bus.battle_failed.connect(_on_battle_ended)
		if not event_bus.battle_started.is_connected(_on_battle_started):
			event_bus.battle_started.connect(_on_battle_started)


func setup(
		camera: Camera3D,
		selection_rect: Control,
		battlefield_bounds: BattlefieldBounds = null,
		water_height_m: float = 0.0
) -> void:
	_camera = camera as RTSCamera
	_selection_rect = selection_rect
	_battlefield_bounds = battlefield_bounds
	_water_height_m = water_height_m
	_input_enabled = true
	if _selection_rect != null:
		_selection_rect.visible = false
	set_process(true)


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		cancel_drag()
		clear_selection()


func is_input_enabled() -> bool:
	return _input_enabled


func _process(_delta: float) -> void:
	_prune_selection()


func has_selection() -> bool:
	_prune_selection()
	return not selected_squadrons.is_empty()


func get_selected_squadrons() -> Array[AircraftSquadron]:
	_prune_selection()
	return selected_squadrons.duplicate()


func clear_selection() -> void:
	if selected_squadrons.is_empty():
		return
	for squadron in selected_squadrons:
		if is_instance_valid(squadron):
			squadron.set_player_selected(false)
	selected_squadrons.clear()
	var empty_selection: Array[AircraftSquadron] = []
	selection_changed.emit(empty_selection)


func select_squadron(
		squadron: AircraftSquadron,
		additive: bool = false
) -> void:
	if not _is_selectable_squadron(squadron):
		return
	if not additive:
		clear_selection()
	if not selected_squadrons.has(squadron):
		selected_squadrons.append(squadron)
		squadron.set_player_selected(true)
		_connect_dive_feedback(squadron)
	selection_changed.emit(get_selected_squadrons())


func begin_drag(screen_position: Vector2) -> bool:
	if not _input_enabled or _camera == null:
		return false
	_drag_start = screen_position
	_drag_current = screen_position
	_dragging = true
	_update_selection_rect()
	return true


func update_drag(screen_position: Vector2) -> void:
	if not _dragging:
		return
	_drag_current = screen_position
	_update_selection_rect()


func finish_drag(
		screen_position: Vector2,
		additive: bool = false
) -> bool:
	if not _dragging:
		return false
	_drag_current = screen_position
	_dragging = false
	if _selection_rect != null:
		_selection_rect.visible = false
	if _drag_start.distance_to(_drag_current) \
			< minimum_drag_distance_pixels:
		return _finish_click_selection(_drag_current, additive)
	var selection_bounds := Rect2(
		_drag_start,
		_drag_current - _drag_start
	).abs()
	if not additive:
		clear_selection()
	for squadron in _get_selection_candidates():
		if _is_squadron_inside_selection(squadron, selection_bounds) \
				and not selected_squadrons.has(squadron):
			selected_squadrons.append(squadron)
			squadron.set_player_selected(true)
			_connect_dive_feedback(squadron)
	selection_changed.emit(get_selected_squadrons())
	_last_input_consumer = "aircraft_drag_selection"
	return true


func cancel_drag() -> void:
	_dragging = false
	if _selection_rect != null:
		_selection_rect.visible = false


func issue_move_command(
		world_position: Vector3,
		attack_target: ShipUnit = null
) -> bool:
	if not _input_enabled:
		return false
	var squadrons := get_selected_squadrons()
	if squadrons.is_empty():
		return false
	var column_count := ceili(sqrt(float(squadrons.size())))
	var row_count := ceili(
		float(squadrons.size()) / float(column_count)
	)
	var issued := false
	for index in squadrons.size():
		var column := index % column_count
		var row := index / column_count
		var offset := Vector3(
			(float(column) - float(column_count - 1) * 0.5) \
				* squadron_command_spacing_m,
			0.0,
			(float(row) - float(row_count - 1) * 0.5) \
				* squadron_command_spacing_m
		)
		var destination := world_position + offset
		if _battlefield_bounds != null:
			destination = _battlefield_bounds.clamp_to_bounds(
				destination,
				battlefield_boundary_margin_m
			)
		issued = squadrons[index].issue_player_move_command(
			destination,
			attack_target
		) or issued
	if issued:
		_last_right_click_position = world_position
		_last_input_consumer = "aircraft_move_command"
	return issued


func issue_move_from_screen(
		screen_position: Vector2,
		attack_target: ShipUnit = null
) -> bool:
	if _camera == null:
		return false
	var point: Variant = _camera.screen_to_sea_plane(screen_position)
	if point == null:
		return false
	var world_position := point as Vector3
	world_position.y = _water_height_m
	return issue_move_command(world_position, attack_target)


func execute_special_action() -> bool:
	if not _input_enabled:
		return false
	var handled := false
	var attempted := false
	for squadron in get_selected_squadrons():
		if squadron.get_aircraft_role() \
			!= AircraftData.AircraftRole.DIVE_BOMBER:
			continue
		attempted = true
		if squadron.can_begin_manual_dive():
			if squadron.begin_manual_dive():
				command_feedback.emit(
					"Dive attack started. Bombs release at each "
					+ "aircraft's safe altitude."
				)
				handled = true
		elif squadron.dive_bomb_controller != null \
				and squadron.dive_bomb_controller.is_active():
			command_feedback.emit(
				"Dive attack already in progress"
			)
	if handled:
		_last_input_consumer = "aircraft_special_action"
	elif attempted:
		_last_input_consumer = "aircraft_special_action_blocked"
	return handled or attempted


func get_debug_snapshot() -> Dictionary:
	var names: Array[String] = []
	for squadron in get_selected_squadrons():
		names.append(squadron.name)
	return {
		"selected_squadron_count": names.size(),
		"selected_squadron_names": names,
		"dragging": _dragging,
		"last_right_click_position": _last_right_click_position,
		"last_input_consumer": _last_input_consumer,
		"selection_candidate_count": _last_candidate_count,
	}


func _connect_dive_feedback(squadron: AircraftSquadron) -> void:
	if squadron == null or squadron.dive_bomb_controller == null:
		return
	var controller := squadron.dive_bomb_controller
	var completed_callback := \
		_on_aircraft_automatic_release_completed.bind(squadron)
	if not controller.aircraft_automatic_release_completed.is_connected(
		completed_callback
	):
		controller.aircraft_automatic_release_completed.connect(
			completed_callback
		)
	var pass_callback := _on_automatic_release_pass_completed.bind(
		squadron
	)
	if not controller.automatic_release_pass_completed.is_connected(
		pass_callback
	):
		controller.automatic_release_pass_completed.connect(pass_callback)


func _on_aircraft_automatic_release_completed(
		_aircraft_id: int,
		released_count: int,
		total_count: int,
		squadron: AircraftSquadron
) -> void:
	if not selected_squadrons.has(squadron):
		return
	command_feedback.emit(
		"Bomb release: %d/%d" % [released_count, total_count]
	)


func _on_automatic_release_pass_completed(
		released_count: int,
		failed_count: int,
		_skipped_count: int,
		_cancelled: bool,
		squadron: AircraftSquadron
) -> void:
	if not selected_squadrons.has(squadron):
		return
	command_feedback.emit(
		"Dive attack complete: %d released, %d failed"
		% [released_count, failed_count]
	)


func _get_selection_candidates() -> Array[AircraftSquadron]:
	var result: Array[AircraftSquadron] = []
	if get_tree() == null:
		return result
	for value in get_tree().get_nodes_in_group(&"aircraft_squadrons"):
		var squadron := value as AircraftSquadron
		if _is_selectable_squadron(squadron):
			result.append(squadron)
		elif debug_selection and squadron != null:
			print_debug(
				"Aircraft selection blocked: squadron=%s reason=%s"
				% [
					squadron.name,
					SelectionBlockReason.keys()[
						int(get_selection_block_reason(squadron))
					],
				]
			)
	_last_candidate_count = result.size()
	return result


func _is_selectable_squadron(
		squadron: AircraftSquadron
) -> bool:
	return get_selection_block_reason(squadron) \
		== SelectionBlockReason.NONE


func get_selection_block_reason(
		squadron: AircraftSquadron
) -> SelectionBlockReason:
	if squadron == null or not is_instance_valid(squadron):
		return SelectionBlockReason.INVALID
	if squadron.is_queued_for_deletion():
		return SelectionBlockReason.QUEUED_FOR_DELETION
	match squadron.state:
		AircraftSquadron.State.RETURNING:
			return SelectionBlockReason.RETURNING
		AircraftSquadron.State.RECOVERING:
			return SelectionBlockReason.RECOVERING
		AircraftSquadron.State.DESTROYED:
			return SelectionBlockReason.DESTROYED
	if squadron.get_alive_aircraft_count() <= 0:
		return SelectionBlockReason.NO_AIRCRAFT
	var carrier := squadron.get_owner_carrier()
	if carrier == null or not is_instance_valid(carrier):
		return SelectionBlockReason.NO_CARRIER
	if not carrier.player_controlled:
		return SelectionBlockReason.CARRIER_NOT_PLAYER_CONTROLLED
	if squadron.get_team() != FactionRelations.PLAYER:
		return SelectionBlockReason.WRONG_TEAM
	return SelectionBlockReason.NONE


func _is_squadron_inside_selection(
		squadron: AircraftSquadron,
		selection_bounds: Rect2
) -> bool:
	if _is_world_point_inside_selection(
		squadron.formation_center,
		selection_bounds
	):
		return true
	for aircraft in squadron.get_alive_aircraft():
		if _is_world_point_inside_selection(
			aircraft.global_position,
			selection_bounds
		):
			return true
	return false


func _is_world_point_inside_selection(
		world_position: Vector3,
		selection_bounds: Rect2
) -> bool:
	if _camera == null or _camera.is_position_behind(world_position):
		return false
	return selection_bounds.has_point(
		_camera.unproject_position(world_position)
	)


func _finish_click_selection(
		screen_position: Vector2,
		additive: bool
) -> bool:
	var closest: AircraftSquadron
	var closest_distance := click_selection_radius_pixels
	for squadron in _get_selection_candidates():
		var points: Array[Vector3] = [squadron.formation_center]
		for aircraft in squadron.get_alive_aircraft():
			points.append(aircraft.global_position)
		for world_position in points:
			if _camera.is_position_behind(world_position):
				continue
			var distance := screen_position.distance_to(
				_camera.unproject_position(world_position)
			)
			if distance <= closest_distance:
				closest = squadron
				closest_distance = distance
	if closest == null:
		return false
	select_squadron(closest, additive)
	_last_input_consumer = "aircraft_click_selection"
	return true


func _prune_selection() -> void:
	var changed := false
	for index in range(selected_squadrons.size() - 1, -1, -1):
		var squadron := selected_squadrons[index]
		if not _is_selectable_squadron(squadron):
			if is_instance_valid(squadron):
				squadron.set_player_selected(false)
			selected_squadrons.remove_at(index)
			changed = true
	if changed:
		selection_changed.emit(get_selected_squadrons())


func _update_selection_rect() -> void:
	if _selection_rect == null:
		return
	var bounds := Rect2(
		_drag_start,
		_drag_current - _drag_start
	).abs()
	_selection_rect.position = bounds.position
	_selection_rect.size = bounds.size
	_selection_rect.visible = true


func _on_battle_ended(_stage_id: String) -> void:
	_input_enabled = false
	cancel_drag()
	clear_selection()


func _on_battle_started(_stage_id: String) -> void:
	_input_enabled = true
