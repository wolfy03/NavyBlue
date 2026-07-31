extends Camera3D
class_name RTSCamera

@export_category("Height (meters)")
@export var min_height_m := 80.0
@export var max_height_m := 7000.0
@export var default_height_m := 1200.0
@export var single_ship_focus_height_m := 650.0

@export_category("View")
@export_range(-80.0, -25.0, 0.5) var pitch_deg := -55.0
@export var default_yaw_deg := 0.0
@export_range(45.0, 70.0, 1.0) var default_fov_deg := 55.0
@export var near_clip_m := 1.0
@export var far_clip_m := 40000.0

@export_category("Movement")
@export var min_move_speed_mps := 450.0
@export var max_move_speed_mps := 2400.0
@export var fast_move_multiplier := 2.0
@export var rotation_speed_deg_sec := 70.0
@export var movement_smoothing_sec := 0.2
@export var focus_smoothing_sec := 0.35
@export var boundary_padding_m := 300.0

@export_category("Mouse")
@export var edge_scroll_enabled := true
@export var edge_margin_pixels := 72.0
@export var drag_pan_scale := 3.0
@export var zoom_factor_per_step := 0.82
@export var zoom_smoothing_sec := 0.24

var focus_position := Vector3.ZERO
var current_height_m := 1200.0
var target_height_m := 1200.0
var current_move_speed_mps := 0.0

var battlefield_settings: BattlefieldSettings
var battlefield_bounds: BattlefieldBounds
var battle_environment: BattleEnvironment
var selection_provider: PlayerInputManager

var _yaw_rad := 0.0
var _pan_velocity := Vector3.ZERO
var _dragging := false
var _focus_transition_active := false
var _focus_target_position := Vector3.ZERO
var _focus_target_height_m := 1200.0
var _zoom_anchor_world: Variant
var _zoom_anchor_screen := Vector2.ZERO

func setup(
		start_focus,
		settings: BattlefieldSettings = null,
		bounds: BattlefieldBounds = null,
		provider: PlayerInputManager = null,
		environment: BattleEnvironment = null
) -> void:
	battlefield_settings = settings
	battlefield_bounds = bounds
	selection_provider = provider
	battle_environment = environment
	if settings != null:
		min_height_m = settings.camera_min_height_m
		max_height_m = settings.camera_max_height_m
		default_height_m = settings.camera_default_height_m
		boundary_padding_m = settings.camera_boundary_padding_m
		min_move_speed_mps = settings.camera_min_move_speed_mps
		max_move_speed_mps = settings.camera_max_move_speed_mps
	# Double the top-end pan speed (WASD / edge-scroll) regardless of whether it
	# came from the exported default or the battlefield settings.
	max_move_speed_mps *= 2.0
	current_height_m = clampf(default_height_m, min_height_m, max_height_m)
	target_height_m = current_height_m
	_yaw_rad = deg_to_rad(default_yaw_deg)
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = default_fov_deg
	near = near_clip_m
	far = far_clip_m
	current = true
	if start_focus is Node3D:
		focus_position = (start_focus as Node3D).global_position
	focus_position.y = _get_sea_level_m()
	_clamp_focus_position()
	_apply_camera_transform()

func set_selection_provider(provider: PlayerInputManager) -> void:
	selection_provider = provider

func _process(delta: float) -> void:
	_handle_action_shortcuts()
	var input_direction := Input.get_vector(
		&"camera_move_left",
		&"camera_move_right",
		&"camera_move_forward",
		&"camera_move_backward"
	)
	input_direction += _get_edge_pan_direction()
	if input_direction.length_squared() > 1.0:
		input_direction = input_direction.normalized()

	var has_manual_motion := input_direction.length_squared() > 0.001 or _dragging
	if has_manual_motion:
		_focus_transition_active = false
		# Release any active zoom-to-cursor anchor so manual panning is not
		# cancelled out by the anchor re-centring the view every frame.
		_zoom_anchor_world = null

	var zoom_ratio := clampf(inverse_lerp(min_height_m, max_height_m, current_height_m), 0.0, 1.0)
	current_move_speed_mps = lerpf(min_move_speed_mps, max_move_speed_mps, zoom_ratio)
	if Input.is_action_pressed(&"camera_fast_move"):
		current_move_speed_mps *= fast_move_multiplier

	var target_velocity := _screen_pan_to_world(input_direction) * current_move_speed_mps
	var movement_weight := _smoothing_weight(delta, movement_smoothing_sec)
	_pan_velocity = _pan_velocity.lerp(target_velocity, movement_weight)
	if _pan_velocity.length_squared() < 0.01:
		_pan_velocity = Vector3.ZERO
	focus_position += _pan_velocity * delta

	var rotation_axis := Input.get_axis(&"camera_rotate_left", &"camera_rotate_right")
	if absf(rotation_axis) > 0.001:
		_focus_transition_active = false
		_yaw_rad = wrapf(_yaw_rad + rotation_axis * deg_to_rad(rotation_speed_deg_sec) * delta, -PI, PI)

	if _focus_transition_active:
		var focus_weight := _smoothing_weight(delta, focus_smoothing_sec)
		focus_position = focus_position.lerp(_focus_target_position, focus_weight)
		target_height_m = lerpf(target_height_m, _focus_target_height_m, focus_weight)
		if focus_position.distance_squared_to(_focus_target_position) < 1.0 \
				and absf(target_height_m - _focus_target_height_m) < 0.5:
			_focus_transition_active = false

	current_height_m = lerpf(current_height_m, target_height_m, _smoothing_weight(delta, zoom_smoothing_sec))
	current_height_m = clampf(current_height_m, min_height_m, max_height_m)
	_clamp_focus_position()
	_apply_camera_transform()
	_apply_zoom_anchor()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_drag"):
		_dragging = true
		_focus_transition_active = false
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"camera_drag"):
		_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_drag_pan(event.relative)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"camera_zoom_in"):
		adjust_zoom(1.0, get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"camera_zoom_out"):
		adjust_zoom(-1.0, get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()

func adjust_zoom(step_count: float, screen_position: Vector2 = Vector2.INF) -> void:
	if screen_position != Vector2.INF:
		_zoom_anchor_screen = screen_position
		_zoom_anchor_world = screen_to_sea_plane(screen_position)
	target_height_m = clampf(
		target_height_m * pow(zoom_factor_per_step, step_count),
		min_height_m,
		max_height_m
	)

func focus_selection() -> void:
	var selected: Array[ShipUnit] = []
	if selection_provider != null:
		selected = selection_provider.get_selected_ships()
	if selected.is_empty() and selection_provider != null:
		var controlled := selection_provider.get_controlled_ship()
		if controlled != null and is_instance_valid(controlled):
			selected.append(controlled)
	focus_on_nodes(selected)

func focus_on_nodes(nodes: Array) -> void:
	var valid_nodes: Array[Node3D] = []
	for node in nodes:
		if is_instance_valid(node) and node is Node3D:
			valid_nodes.append(node as Node3D)
	if valid_nodes.is_empty():
		return

	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for node in valid_nodes:
		minimum.x = minf(minimum.x, node.global_position.x)
		minimum.y = minf(minimum.y, node.global_position.z)
		maximum.x = maxf(maximum.x, node.global_position.x)
		maximum.y = maxf(maximum.y, node.global_position.z)
	var center := (minimum + maximum) * 0.5
	var fleet_radius := (maximum - minimum).length() * 0.5
	var required_height := single_ship_focus_height_m
	if valid_nodes.size() > 1:
		required_height = maxf(single_ship_focus_height_m, fleet_radius / tan(deg_to_rad(fov * 0.5)) * 1.25)
	_start_focus_transition(Vector3(center.x, _get_sea_level_m(), center.y), required_height)

func reset_to_battlefield_center() -> void:
	_yaw_rad = deg_to_rad(default_yaw_deg)
	_start_focus_transition(Vector3(0.0, _get_sea_level_m(), 0.0), default_height_m)

func screen_to_sea_plane(screen_position: Vector2) -> Variant:
	var origin := project_ray_origin(screen_position)
	var direction := project_ray_normal(screen_position)
	if absf(direction.y) < 0.00001:
		return null
	var distance := (_get_sea_level_m() - origin.y) / direction.y
	if distance < 0.0:
		return null
	return origin + direction * distance

func get_camera_debug_data() -> Dictionary:
	return {
		"focus_position": focus_position,
		"height_m": current_height_m,
		"move_speed_mps": current_move_speed_mps,
	}

func _handle_action_shortcuts() -> void:
	if Input.is_action_just_pressed(&"camera_focus_selection"):
		focus_selection()
	if Input.is_action_just_pressed(&"camera_reset"):
		reset_to_battlefield_center()

func _drag_pan(relative: Vector2) -> void:
	var viewport_height := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var world_per_pixel := current_height_m * 2.0 * tan(deg_to_rad(fov * 0.5)) / viewport_height
	var world_delta := _screen_pan_to_world(relative) * world_per_pixel * drag_pan_scale
	focus_position -= world_delta
	_clamp_focus_position()
	_apply_camera_transform()

func _get_edge_pan_direction() -> Vector2:
	if not edge_scroll_enabled or not get_viewport().get_visible_rect().has_point(get_viewport().get_mouse_position()):
		return Vector2.ZERO
	var mouse_position := get_viewport().get_mouse_position()
	var viewport_size := get_viewport().get_visible_rect().size
	var direction := Vector2.ZERO
	if mouse_position.x <= edge_margin_pixels:
		direction.x -= 1.0
	elif mouse_position.x >= viewport_size.x - edge_margin_pixels:
		direction.x += 1.0
	if mouse_position.y <= edge_margin_pixels:
		direction.y -= 1.0
	elif mouse_position.y >= viewport_size.y - edge_margin_pixels:
		direction.y += 1.0
	return direction

func _screen_pan_to_world(screen_direction: Vector2) -> Vector3:
	var camera_forward := -global_transform.basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()
	var camera_right := global_transform.basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()
	return camera_right * screen_direction.x + camera_forward * -screen_direction.y

func _apply_camera_transform() -> void:
	var pitch_radians := deg_to_rad(clampf(pitch_deg, -80.0, -25.0))
	var horizontal_distance := current_height_m / tan(absf(pitch_radians))
	var offset := Vector3(sin(_yaw_rad) * horizontal_distance, current_height_m, cos(_yaw_rad) * horizontal_distance)
	global_position = focus_position + offset
	look_at(focus_position, Vector3.UP)

func _apply_zoom_anchor() -> void:
	if _zoom_anchor_world == null:
		return
	var current_anchor: Variant = screen_to_sea_plane(_zoom_anchor_screen)
	if current_anchor != null:
		var correction: Vector3 = _zoom_anchor_world - current_anchor
		correction.y = 0.0
		focus_position += correction
		_clamp_focus_position()
		_apply_camera_transform()
	if absf(current_height_m - target_height_m) < 0.5:
		_zoom_anchor_world = null

func _start_focus_transition(world_position: Vector3, height_m: float) -> void:
	_focus_target_position = world_position
	_focus_target_position.y = _get_sea_level_m()
	_focus_target_height_m = clampf(height_m, min_height_m, max_height_m)
	_focus_transition_active = true
	_zoom_anchor_world = null

func _clamp_focus_position() -> void:
	var height_ratio := clampf(inverse_lerp(min_height_m, max_height_m, current_height_m), 0.0, 1.0)
	var padding := boundary_padding_m + height_ratio * 200.0
	if battlefield_bounds != null and battlefield_bounds.settings != null:
		var half_extents := battlefield_bounds.settings.get_half_extents_m()
		focus_position.x = clampf(focus_position.x, -half_extents.x - padding, half_extents.x + padding)
		focus_position.z = clampf(focus_position.z, -half_extents.y - padding, half_extents.y + padding)
	focus_position.y = _get_sea_level_m()

func _get_sea_level_m() -> float:
	if battle_environment != null:
		return battle_environment.sea_level_m
	return battlefield_settings.sea_level_m \
		if battlefield_settings != null else 0.0

func _smoothing_weight(delta: float, smoothing_sec: float) -> float:
	if smoothing_sec <= 0.0001:
		return 1.0
	return 1.0 - exp(-delta / smoothing_sec)
