extends Node
class_name PlayerInputManager

signal selection_changed(selected_ships: Array)
signal move_command_issued(target: Vector3, ships: Array)

@export var water_height_m := 0.0
@export var pitch_step_degrees := 1.5
@export var selection_ray_length_m := 50000.0
@export var formation_spacing_m := 320.0
@export var command_boundary_margin_m := 250.0
@export var movement_marker_path: NodePath = ^"../MovementMarker"

var controlled_ship
var camera: RTSCamera
var battlefield_bounds: BattlefieldBounds
var selected_ships: Array[Node3D] = []
var _movement_marker: Node3D

func setup(ship, view_camera: Camera3D, water_y: float = 0.0, bounds: BattlefieldBounds = null) -> void:
	controlled_ship = ship
	camera = view_camera as RTSCamera
	water_height_m = water_y
	battlefield_bounds = bounds
	_movement_marker = get_node_or_null(movement_marker_path) as Node3D
	if is_instance_valid(controlled_ship):
		_select_only(controlled_ship)
	if camera != null:
		camera.set_selection_provider(self)

func _physics_process(_delta: float) -> void:
	_prune_selection()
	if not is_instance_valid(controlled_ship):
		return
	var throttle_axis := Input.get_axis(&"ship_throttle_reverse", &"ship_throttle_forward")
	var rudder_axis := Input.get_axis(&"ship_rudder_right", &"ship_rudder_left")
	var fire_pressed := Input.is_action_pressed(&"ship_fire")
	controlled_ship.set_player_commands(throttle_axis, rudder_axis, fire_pressed)
	if Input.is_action_just_pressed(&"turret_pitch_up"):
		_adjust_selected_turret_pitch(pitch_step_degrees)
	if Input.is_action_just_pressed(&"turret_pitch_down"):
		_adjust_selected_turret_pitch(-pitch_step_degrees)
	if Input.is_action_just_pressed(&"command_cancel"):
		cancel_selected_commands()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or _is_pointer_over_ui():
		return
	var mouse_event := event as InputEventMouseButton
	match mouse_event.button_index:
		MOUSE_BUTTON_LEFT:
			_handle_primary_click(mouse_event.position)
		MOUSE_BUTTON_RIGHT:
			_issue_move_command_from_screen(mouse_event.position)

func get_selected_ships() -> Array:
	_prune_selection()
	return selected_ships.duplicate()

func get_controlled_ship():
	return controlled_ship

func cancel_selected_commands() -> void:
	for ship in selected_ships:
		if is_instance_valid(ship) and ship.has_method(&"clear_navigation_target"):
			ship.call(&"clear_navigation_target")
	if _movement_marker != null:
		_movement_marker.visible = false

func _handle_primary_click(screen_position: Vector2) -> void:
	var aim_point: Variant = _screen_to_water(screen_position)
	if aim_point != null and is_instance_valid(controlled_ship):
		if battlefield_bounds != null:
			aim_point = battlefield_bounds.clamp_to_bounds(aim_point, command_boundary_margin_m)
		controlled_ship.set_aim_point(aim_point)

func _issue_move_command_from_screen(screen_position: Vector2) -> void:
	var target = _screen_to_water(screen_position)
	if target == null:
		return
	if battlefield_bounds != null:
		target = battlefield_bounds.clamp_to_bounds(target, command_boundary_margin_m)
	var valid_ships: Array[Node3D] = []
	for ship in selected_ships:
		if is_instance_valid(ship) and ship.has_method(&"set_navigation_target"):
			valid_ships.append(ship)
	if valid_ships.is_empty():
		return

	var column_count := ceili(sqrt(float(valid_ships.size())))
	var row_count := ceili(float(valid_ships.size()) / float(column_count))
	for index in valid_ships.size():
		var column := index % column_count
		var row := index / column_count
		var offset := Vector3(
			(float(column) - float(column_count - 1) * 0.5) * formation_spacing_m,
			0.0,
			(float(row) - float(row_count - 1) * 0.5) * formation_spacing_m
		)
		var ship_target: Vector3 = target + offset
		if battlefield_bounds != null:
			ship_target = battlefield_bounds.clamp_to_bounds(ship_target, command_boundary_margin_m)
		valid_ships[index].call(&"set_navigation_target", ship_target)

	if _movement_marker != null:
		_movement_marker.visible = true
		_movement_marker.global_position = target + Vector3(0.0, 2.0, 0.0)
	move_command_issued.emit(target, valid_ships)

func _pick_ship(screen_position: Vector2) -> Node3D:
	if camera == null or camera.get_world_3d() == null:
		return null
	var origin := camera.project_ray_origin(screen_position)
	var ray_end := origin + camera.project_ray_normal(screen_position) * selection_ray_length_m
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collide_with_areas = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var candidate: Node = hit.get("collider") as Node
	while candidate != null:
		if candidate.is_in_group(&"ships"):
			return candidate as Node3D
		candidate = candidate.get_parent()
	return null

func _screen_to_water(screen_position: Vector2) -> Variant:
	if camera == null:
		return null
	var point = camera.screen_to_sea_plane(screen_position)
	if point != null:
		point.y = water_height_m
	return point

func _select_only(ship: Node3D) -> void:
	selected_ships.clear()
	if is_instance_valid(ship):
		selected_ships.append(ship)
	selection_changed.emit(get_selected_ships())

func _toggle_selection(ship: Node3D) -> void:
	var index := selected_ships.find(ship)
	if index >= 0:
		selected_ships.remove_at(index)
	else:
		selected_ships.append(ship)
	selection_changed.emit(get_selected_ships())

func _prune_selection() -> void:
	for index in range(selected_ships.size() - 1, -1, -1):
		if not is_instance_valid(selected_ships[index]):
			selected_ships.remove_at(index)

func _is_pointer_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE

func _adjust_selected_turret_pitch(delta_degrees: float) -> void:
	for ship in selected_ships:
		if is_instance_valid(ship) and ship.has_method(&"adjust_turret_pitch"):
			ship.call(&"adjust_turret_pitch", delta_degrees)
