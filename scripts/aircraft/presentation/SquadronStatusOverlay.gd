extends PanelContainer
class_name SquadronStatusOverlay

@onready var status_label: Label = %StatusLabel

var _squadron_ref: WeakRef
var _last_viewport_size := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	if not minimum_size_changed.is_connected(
		_on_minimum_size_changed
	):
		minimum_size_changed.connect(_on_minimum_size_changed)


func activate(squadron: AircraftSquadron) -> void:
	_squadron_ref = weakref(squadron) \
		if squadron != null and is_instance_valid(squadron) else null
	set_process(false)


func deactivate() -> void:
	_squadron_ref = null
	_last_viewport_size = Vector2.ZERO
	visible = false
	set_process(false)
	set_physics_process(false)


func set_snapshot(snapshot: SquadronPresentationSnapshot) -> void:
	if snapshot == null:
		visible = false
		return
	status_label.text = (
		"%s  %s\n"
		+ "%s  %d/%d\n"
		+ "HP %d%%  %.0f m/s\n"
		+ "%s  %d\n"
		+ "%s"
	) % [
		snapshot.display_name,
		snapshot.role_name,
		snapshot.state_name,
		snapshot.alive_count,
		snapshot.total_count,
		roundi(snapshot.average_health_ratio * 100.0),
		snapshot.average_speed_mps,
		snapshot.weapon_name,
		snapshot.ammunition_count,
		snapshot.mission_name,
	]
	reset_size()
	size = get_combined_minimum_size()


func set_screen_bounds(
		camera: Camera3D,
		bounds: AABB,
		offset_pixels: Vector2
) -> void:
	if camera == null or not is_instance_valid(camera):
		visible = false
		return
	var screen_bounds := get_screen_bounds(camera, bounds)
	if screen_bounds.size == Vector2.ZERO:
		visible = false
		return
	var viewport_size := camera.get_viewport() \
		.get_visible_rect().size
	var viewport_bounds := Rect2(Vector2.ZERO, viewport_size)
	if not viewport_bounds.intersects(screen_bounds, true):
		visible = false
		return
	_last_viewport_size = viewport_size
	position = screen_bounds.end + offset_pixels
	_clamp_to_viewport()
	visible = true


static func get_screen_bounds(
		camera: Camera3D,
		bounds: AABB
) -> Rect2:
	if camera == null or not is_instance_valid(camera):
		return Rect2()
	var has_point := false
	var minimum := Vector2.ZERO
	var maximum := Vector2.ZERO
	for corner_index in 8:
		var world_corner := bounds.get_endpoint(corner_index)
		if camera.is_position_behind(world_corner):
			continue
		var screen_point := camera.unproject_position(world_corner)
		if not has_point:
			minimum = screen_point
			maximum = screen_point
			has_point = true
		else:
			minimum.x = minf(minimum.x, screen_point.x)
			minimum.y = minf(minimum.y, screen_point.y)
			maximum.x = maxf(maximum.x, screen_point.x)
			maximum.y = maxf(maximum.y, screen_point.y)
	if not has_point:
		return Rect2()
	return Rect2(minimum, maximum - minimum)


func _clamp_to_viewport() -> void:
	if _last_viewport_size == Vector2.ZERO:
		return
	var maximum_position := Vector2(
		maxf(_last_viewport_size.x - size.x, 0.0),
		maxf(_last_viewport_size.y - size.y, 0.0)
	)
	position = position.clamp(Vector2.ZERO, maximum_position)


func _on_minimum_size_changed() -> void:
	size = get_combined_minimum_size()
	_clamp_to_viewport()
