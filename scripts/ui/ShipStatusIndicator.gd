extends Control
class_name ShipStatusIndicator

const HEALTH_BAR_HEIGHT: float = 7.0
const HEALTH_BAR_GAP: float = 3.0
const STATUS_PANEL_SIZE := Vector2(44.0, 16.0)

@export var minimum_frame_size := Vector2(42.0, 26.0)
@export_range(0.0, 30.0, 1.0) var frame_pixel_padding: float = 5.0
@export_range(0.0, 2.0, 0.05) var hull_width_scale: float = 0.62
@export_range(0.0, 2.0, 0.05) var hull_length_scale: float = 0.66
@export_range(0.0, 5.0, 0.05) var height_padding_world: float = 0.9
@export_range(1.0, 4.0, 0.1) var frame_line_width: float = 1.5

@onready var status_panel: PanelContainer = $StatusPanel
@onready var status_label: Label = $StatusPanel/StatusLabel

var target_ship: Node3D
var battle_camera: Camera3D
var _health: ShipHealth
var _frame_height: float = 0.0
var _health_ratio: float = 1.0
var _team_color := Color(0.25, 0.9, 0.75)
var _status_text: String = "MOVE"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.size = STATUS_PANEL_SIZE
	_apply_status_style()
	set_process(target_ship != null)


func setup(ship: Node3D, camera: Camera3D) -> void:
	target_ship = ship
	battle_camera = camera
	_team_color = _resolve_team_color()
	_health = target_ship.get_node_or_null("ShipHealth") as ShipHealth
	if _health != null \
			and not _health.damage_result_applied.is_connected(
				_on_damage_result_applied
			):
		_health.damage_result_applied.connect(_on_damage_result_applied)
	_apply_status_style()
	_refresh_health()
	set_process(true)


func _process(_delta: float) -> void:
	if not is_instance_valid(target_ship):
		queue_free()
		return
	if not is_instance_valid(battle_camera):
		battle_camera = get_viewport().get_camera_3d()
	if battle_camera == null:
		visible = false
		return

	var projected_rect: Rect2 = _calculate_projected_rect()
	if projected_rect.size.x <= 0.0 or projected_rect.size.y <= 0.0:
		visible = false
		return
	var viewport_rect: Rect2 = get_viewport_rect()
	var full_rect := Rect2(
		projected_rect.position,
		projected_rect.size + Vector2(0.0, HEALTH_BAR_GAP + HEALTH_BAR_HEIGHT)
	)
	if not viewport_rect.intersects(full_rect):
		visible = false
		return

	visible = true
	position = projected_rect.position
	_frame_height = projected_rect.size.y
	var next_size := Vector2(projected_rect.size.x, _frame_height + HEALTH_BAR_GAP + HEALTH_BAR_HEIGHT)
	if not size.is_equal_approx(next_size):
		size = next_size
		queue_redraw()
	status_panel.position = Vector2(maxf(0.0, size.x - STATUS_PANEL_SIZE.x), 0.0)
	_refresh_status()
	_refresh_health()


func _calculate_projected_rect() -> Rect2:
	if battle_camera.is_position_behind(target_ship.global_position):
		return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))

	var hull_size := Vector3(2.0, 1.0, 6.0)
	var ship_data: Variant = target_ship.get(&"ship_data")
	if ship_data != null:
		var configured_size: Variant = ship_data.get(&"hull_size")
		if configured_size is Vector3:
			hull_size = configured_size

	var half_width: float = hull_size.x * hull_width_scale
	var half_length: float = hull_size.z * hull_length_scale
	var top_height: float = hull_size.y + height_padding_world
	var screen_min := Vector2(INF, INF)
	var screen_max := Vector2(-INF, -INF)
	for corner_index: int in 8:
		var local_corner := Vector3(
			-half_width if (corner_index & 1) == 0 else half_width,
			0.0 if (corner_index & 2) == 0 else top_height,
			-half_length if (corner_index & 4) == 0 else half_length
		)
		var world_corner: Vector3 = target_ship.to_global(local_corner)
		if battle_camera.is_position_behind(world_corner):
			return Rect2(Vector2.ZERO, Vector2(-1.0, -1.0))
		var screen_corner: Vector2 = battle_camera.unproject_position(world_corner)
		screen_min.x = minf(screen_min.x, screen_corner.x)
		screen_min.y = minf(screen_min.y, screen_corner.y)
		screen_max.x = maxf(screen_max.x, screen_corner.x)
		screen_max.y = maxf(screen_max.y, screen_corner.y)

	var projected_size: Vector2 = screen_max - screen_min + Vector2.ONE * frame_pixel_padding * 2.0
	var projected_center: Vector2 = (screen_min + screen_max) * 0.5
	projected_size.x = maxf(projected_size.x, minimum_frame_size.x)
	projected_size.y = maxf(projected_size.y, minimum_frame_size.y)
	return Rect2(projected_center - projected_size * 0.5, projected_size)


func _refresh_health() -> void:
	var next_ratio: float = 1.0
	if _health != null:
		var stats: ShipDefenseStats = _health.get_defense_stats()
		next_ratio = clampf(stats.current_hp / maxf(stats.max_hp, 1.0), 0.0, 1.0)
	if not is_equal_approx(next_ratio, _health_ratio):
		_health_ratio = next_ratio
		queue_redraw()


func _refresh_status() -> void:
	var next_status := "MOVE"
	if bool(target_ship.get("_is_sinking")):
		next_status = "SINK"
	elif bool(target_ship.get("player_controlled")):
		next_status = "CMD"
	else:
		var ship_ai: Node = target_ship.get_node_or_null("ShipAI")
		if ship_ai != null:
			match int(ship_ai.get("behavior_state")):
				0:
					next_status = "MOVE"
				1:
					next_status = "ATK"
				2:
					next_status = "RET"
	if next_status == _status_text:
		return
	_status_text = next_status
	status_label.text = _status_text


func _resolve_team_color() -> Color:
	if target_ship == null:
		return Color(0.25, 0.9, 0.75)
	var team_name := StringName(str(target_ship.get("team")))
	match team_name:
		&"player":
			return Color(0.18, 0.82, 1.0)
		&"ally":
			return Color(0.2, 0.92, 0.58)
		&"enemy":
			return Color(1.0, 0.2, 0.14)
	return Color(1.0, 0.72, 0.2)


func _apply_status_style() -> void:
	if not is_node_ready():
		return
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.035, 0.04, 0.86)
	panel_style.border_color = _team_color
	panel_style.set_border_width_all(1)
	status_panel.add_theme_stylebox_override("panel", panel_style)
	status_label.add_theme_color_override("font_color", _team_color.lightened(0.16))
	status_label.text = _status_text


func _on_damage_result_applied(_result: DamageResult) -> void:
	_refresh_health()


func _draw() -> void:
	if _frame_height <= 0.0:
		return
	var frame_rect := Rect2(Vector2.ZERO, Vector2(size.x, _frame_height))
	var frame_color := Color(_team_color.r, _team_color.g, _team_color.b, 0.88)
	draw_rect(frame_rect, frame_color, false, frame_line_width, true)

	var corner_length: float = clampf(minf(frame_rect.size.x, frame_rect.size.y) * 0.28, 8.0, 18.0)
	_draw_corner(frame_rect.position, Vector2.RIGHT, Vector2.DOWN, corner_length, frame_color)
	_draw_corner(Vector2(frame_rect.end.x, frame_rect.position.y), Vector2.LEFT, Vector2.DOWN, corner_length, frame_color)
	_draw_corner(Vector2(frame_rect.position.x, frame_rect.end.y), Vector2.RIGHT, Vector2.UP, corner_length, frame_color)
	_draw_corner(frame_rect.end, Vector2.LEFT, Vector2.UP, corner_length, frame_color)

	var health_rect := Rect2(
		Vector2(0.0, _frame_height + HEALTH_BAR_GAP),
		Vector2(size.x, HEALTH_BAR_HEIGHT)
	)
	draw_rect(health_rect, Color(0.015, 0.02, 0.022, 0.94), true)
	draw_rect(health_rect, Color(0.0, 0.0, 0.0, 0.9), false, 1.0)
	var inner_rect := health_rect.grow(-1.5)
	inner_rect.size.x *= _health_ratio
	if inner_rect.size.x > 0.0:
		draw_rect(inner_rect, _get_health_color(), true)


func _draw_corner(
		origin: Vector2,
		horizontal_direction: Vector2,
		vertical_direction: Vector2,
		length: float,
		color: Color
) -> void:
	draw_line(origin, origin + horizontal_direction * length, color, frame_line_width + 1.0, true)
	draw_line(origin, origin + vertical_direction * length, color, frame_line_width + 1.0, true)


func _get_health_color() -> Color:
	if _health_ratio > 0.6:
		return Color(0.18, 0.92, 0.35)
	if _health_ratio > 0.3:
		return Color(1.0, 0.76, 0.12)
	return Color(1.0, 0.16, 0.1)
