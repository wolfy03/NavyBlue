extends Camera3D
class_name RTSCamera

@export var view_offset := Vector3(28.0, 34.0, 31.0)
@export var look_direction_target_offset := Vector3.ZERO
@export var edge_margin_pixels := 28.0
@export var pan_speed := 34.0
@export var pan_bounds_min := Vector2(-170.0, -170.0)
@export var pan_bounds_max := Vector2(170.0, 170.0)
@export var zoom_step := 3.0
@export var min_zoom_size := 18.0
@export var max_zoom_size := 120.0

var focus_position := Vector3.ZERO

func setup(start_focus) -> void:
	if start_focus != null:
		focus_position = start_focus.global_position
	_apply_camera_transform()

func _process(delta: float) -> void:
	var pan_direction := _get_edge_pan_direction()
	if pan_direction.length_squared() > 1.0:
		pan_direction = pan_direction.normalized()
	if pan_direction.length_squared() > 0.0:
		focus_position += _screen_pan_to_world(pan_direction) * pan_speed * delta
		focus_position.x = clampf(focus_position.x, pan_bounds_min.x, pan_bounds_max.x)
		focus_position.z = clampf(focus_position.z, pan_bounds_min.y, pan_bounds_max.y)
	_apply_camera_transform()

func adjust_zoom(step_count: float) -> void:
	if projection == Camera3D.PROJECTION_ORTHOGONAL:
		size = clampf(size - step_count * zoom_step, min_zoom_size, max_zoom_size)
	else:
		fov = clampf(fov - step_count * zoom_step, min_zoom_size, max_zoom_size)

func _get_edge_pan_direction() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO

	var mouse_position := viewport.get_mouse_position()
	var viewport_size := viewport.get_visible_rect().size
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

	return camera_right * screen_direction.x - camera_forward * screen_direction.y

func _apply_camera_transform() -> void:
	global_position = focus_position + view_offset
	look_at(focus_position + look_direction_target_offset, Vector3.UP)

