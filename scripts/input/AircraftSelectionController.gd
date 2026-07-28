extends Node
class_name AircraftSelectionController

signal selection_changed(squadrons: Array[AircraftSquadron])

@export var minimum_drag_distance_pixels := 8.0
@export var squadron_command_spacing_m := 150.0
@export var battlefield_boundary_margin_m := 250.0

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
		return false
	var selection_bounds := Rect2(
		_drag_start,
		_drag_current - _drag_start
	).abs()
	if not additive:
		clear_selection()
	for squadron in _get_selection_candidates():
		if _camera.is_position_behind(squadron.formation_center):
			continue
		var screen_position_value := _camera.unproject_position(
			squadron.formation_center
		)
		if selection_bounds.has_point(screen_position_value) \
				and not selected_squadrons.has(squadron):
			selected_squadrons.append(squadron)
			squadron.set_player_selected(true)
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
	for squadron in get_selected_squadrons():
		if squadron.get_aircraft_role() \
				!= AircraftData.AircraftRole.DIVE_BOMBER:
			continue
		match squadron.manual_dive_state:
			AircraftSquadron.ManualDiveCommandState.READY:
				handled = squadron.begin_manual_dive() or handled
			AircraftSquadron.ManualDiveCommandState.DIVING:
				handled = squadron.request_manual_bomb_release() \
					or handled
			_:
				pass
	if handled:
		_last_input_consumer = "aircraft_special_action"
	return handled


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
	}


func _get_selection_candidates() -> Array[AircraftSquadron]:
	var result: Array[AircraftSquadron] = []
	if get_tree() == null:
		return result
	for value in get_tree().get_nodes_in_group(&"aircraft_squadrons"):
		var squadron := value as AircraftSquadron
		if _is_selectable_squadron(squadron):
			result.append(squadron)
	return result


func _is_selectable_squadron(
		squadron: AircraftSquadron
) -> bool:
	if squadron == null or not is_instance_valid(squadron) \
			or squadron.is_queued_for_deletion() \
			or squadron.state in [
				AircraftSquadron.State.RETURNING,
				AircraftSquadron.State.RECOVERING,
				AircraftSquadron.State.DESTROYED,
			] \
			or squadron.get_alive_aircraft_count() <= 0:
		return false
	var carrier := squadron.get_owner_carrier()
	return carrier != null \
		and is_instance_valid(carrier) \
		and carrier.player_controlled \
		and squadron.get_team() == FactionRelations.PLAYER


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
