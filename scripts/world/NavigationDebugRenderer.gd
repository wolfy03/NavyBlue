extends Node3D
class_name NavigationDebugRenderer

const DEFAULT_SETTINGS := preload("res://resources/settings/default_battlefield_settings.tres")

@export var settings: BattlefieldSettings = DEFAULT_SETTINGS
@export var camera_path: NodePath = ^"../RTSCamera"
@export var debug_label_path: NodePath = ^"../HUD/DebugLabel"
@export var redraw_interval_sec := 0.2
@export var ship_vector_length_m := 260.0
@export var avoidance_circle_segments := 24

var enabled := false
var _elapsed_sec := 0.0
var _mesh_instance := MeshInstance3D.new()
var _immediate_mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
var _camera: RTSCamera
var _debug_label: Label
var _ships: Array[Node3D] = []

func _ready() -> void:
	enabled = settings.debug_draw_enabled and not OS.has_feature("release")
	_camera = get_node_or_null(camera_path) as RTSCamera
	_debug_label = get_node_or_null(debug_label_path) as Label
	_configure_mesh()
	_cache_initial_ships()
	_connect_ship_signals()
	_set_debug_visibility(enabled)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"debug_toggle") and not OS.has_feature("release"):
		enabled = not enabled
		_set_debug_visibility(enabled)
	if not enabled:
		return
	_elapsed_sec += delta
	if _elapsed_sec < redraw_interval_sec:
		return
	_elapsed_sec = 0.0
	_prune_ships()
	_redraw()
	_update_debug_label()

func _configure_mesh() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)

func _redraw() -> void:
	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	_draw_grid_and_bounds()
	for ship in _ships:
		_draw_ship_navigation(ship)
	_draw_fleet_tactics()
	_draw_camera_focus()
	_immediate_mesh.surface_end()

func _draw_grid_and_bounds() -> void:
	var half_extents := settings.get_half_extents_m()
	var sea_y := settings.sea_level_m + 1.0
	var spacing := maxf(settings.debug_grid_spacing_m, 100.0)
	var x := -half_extents.x
	while x <= half_extents.x + 0.1:
		_add_line(Vector3(x, sea_y, -half_extents.y), Vector3(x, sea_y, half_extents.y), Color(0.25, 0.75, 1.0, 0.2))
		x += spacing
	var z := -half_extents.y
	while z <= half_extents.y + 0.1:
		_add_line(Vector3(-half_extents.x, sea_y, z), Vector3(half_extents.x, sea_y, z), Color(0.25, 0.75, 1.0, 0.2))
		z += spacing
	var minimum := Vector3(-half_extents.x, sea_y + 1.0, -half_extents.y)
	var maximum := Vector3(half_extents.x, sea_y + 1.0, half_extents.y)
	_add_line(Vector3(minimum.x, sea_y, minimum.z), Vector3(maximum.x, sea_y, minimum.z), Color.CYAN)
	_add_line(Vector3(maximum.x, sea_y, minimum.z), Vector3(maximum.x, sea_y, maximum.z), Color.CYAN)
	_add_line(Vector3(maximum.x, sea_y, maximum.z), Vector3(minimum.x, sea_y, maximum.z), Color.CYAN)
	_add_line(Vector3(minimum.x, sea_y, maximum.z), Vector3(minimum.x, sea_y, minimum.z), Color.CYAN)
	_add_line(Vector3(-100.0, sea_y + 3.0, 0.0), Vector3(100.0, sea_y + 3.0, 0.0), Color.WHITE)
	_add_line(Vector3(0.0, sea_y + 3.0, -100.0), Vector3(0.0, sea_y + 3.0, 100.0), Color.WHITE)

func _draw_ship_navigation(ship: Node3D) -> void:
	if not is_instance_valid(ship):
		return
	var origin := ship.global_position + Vector3.UP * 4.0
	var forward := -ship.global_transform.basis.z
	forward.y = 0.0
	_add_line(origin, origin + forward.normalized() * ship_vector_length_m, Color(0.2, 0.85, 1.0, 0.9))
	var navigation := ship.get_node_or_null("ShipNavigationController") as ShipNavigationController
	if navigation != null and navigation.has_navigation_target:
		var previous := origin
		for index in range(navigation.current_waypoint_index, navigation.current_path.size()):
			var point := navigation.current_path[index] + Vector3.UP * 4.0
			_add_line(previous, point, Color(1.0, 0.82, 0.15, 0.9))
			previous = point
		var waypoint := navigation.get_current_waypoint() + Vector3.UP * 5.0
		_add_cross(waypoint, 45.0, Color(0.2, 1.0, 0.35, 1.0))
		var desired := navigation.get_current_waypoint() - ship.global_position
		desired.y = 0.0
		if desired.length_squared() > 0.01:
			_add_line(origin, origin + desired.normalized() * ship_vector_length_m, Color(1.0, 0.5, 0.15, 0.9))
	var avoidance := ship.get_node_or_null("ShipAvoidanceController") as ShipAvoidanceController
	if avoidance != null:
		_draw_circle(origin, avoidance.avoidance_radius_m, Color(0.9, 0.45, 0.15, 0.28))
		if avoidance.has_collision_risk():
			_add_line(origin, avoidance.collision_risk_ship.global_position + Vector3.UP * 4.0, Color.RED)

func _draw_camera_focus() -> void:
	if _camera == null:
		return
	_add_cross(_camera.focus_position + Vector3.UP * 8.0, 80.0, Color(0.85, 0.25, 1.0, 1.0))


func _draw_fleet_tactics() -> void:
	var battle_scene := get_parent() as BattleScene
	if battle_scene == null:
		return
	for fleet in battle_scene.get_fleet_controllers():
		var center := fleet.fleet_center + Vector3.UP * 10.0
		var fleet_color := Color(0.2, 0.75, 1.0, 0.9) \
			if fleet.fleet_id == &"friendly_main" \
			else Color(1.0, 0.3, 0.2, 0.9)
		_add_cross(center, 120.0, fleet_color)
		_add_line(
			center,
			center + fleet.fleet_average_forward * 500.0,
			fleet_color
		)
		for ship in fleet.get_alive_members():
			var context := fleet.get_member_context(ship)
			if context == null or not context.tactical_position_valid:
				continue
			var tactical_position := context.tactical_position + Vector3.UP * 7.0
			_add_cross(tactical_position, 55.0, fleet_color)
			_add_line(ship.global_position + Vector3.UP * 7.0, tactical_position, fleet_color)

func _draw_circle(center: Vector3, radius: float, color: Color) -> void:
	var previous := center + Vector3(radius, 0.0, 0.0)
	for index in range(1, avoidance_circle_segments + 1):
		var angle := TAU * float(index) / float(avoidance_circle_segments)
		var point := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_add_line(previous, point, color)
		previous = point

func _add_cross(center: Vector3, radius: float, color: Color) -> void:
	_add_line(center - Vector3.RIGHT * radius, center + Vector3.RIGHT * radius, color)
	_add_line(center - Vector3.FORWARD * radius, center + Vector3.FORWARD * radius, color)

func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(from)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(to)

func _update_debug_label() -> void:
	if _debug_label == null or _camera == null:
		return
	var data := _camera.get_camera_debug_data()
	var fleet_summary := ""
	var battle_scene := get_parent() as BattleScene
	if battle_scene != null:
		for fleet in battle_scene.get_fleet_controllers():
			var fleet_data := fleet.get_debug_data()
			fleet_summary += "\n%s: %d ships, eval %d, cleanup %d" % [
				String(fleet.fleet_id),
				int(fleet_data["member_count"]),
				int(fleet_data["fleet_evaluation_count"]),
				int(fleet_data["tracker_cleanup_count"]),
			]
	_debug_label.text = "Battlefield debug\nCamera center: (%.0f, %.0f)m\nHeight: %.0fm\nMove speed: %.0fm/s\nShips: %d%s" % [
		data["focus_position"].x,
		data["focus_position"].z,
		data["height_m"],
		data["move_speed_mps"],
		_ships.size(),
		fleet_summary,
	]

func _cache_initial_ships() -> void:
	for node in get_tree().get_nodes_in_group(&"ships"):
		_on_ship_spawned(node)

func _connect_ship_signals() -> void:
	if not has_node("/root/EventBus"):
		return
	var event_bus := get_node("/root/EventBus")
	if not event_bus.ship_spawned.is_connected(_on_ship_spawned):
		event_bus.ship_spawned.connect(_on_ship_spawned)
	if not event_bus.ship_destroyed.is_connected(_on_ship_destroyed):
		event_bus.ship_destroyed.connect(_on_ship_destroyed)

func _on_ship_spawned(ship) -> void:
	if ship is Node3D and not _ships.has(ship):
		_ships.append(ship)

func _on_ship_destroyed(ship) -> void:
	_ships.erase(ship)

func _prune_ships() -> void:
	for index in range(_ships.size() - 1, -1, -1):
		if not is_instance_valid(_ships[index]):
			_ships.remove_at(index)

func _set_debug_visibility(value: bool) -> void:
	_mesh_instance.visible = value
	if _debug_label != null:
		_debug_label.visible = value
