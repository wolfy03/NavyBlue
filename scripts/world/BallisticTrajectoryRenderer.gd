extends Node3D
class_name BallisticTrajectoryRenderer

@export_category("Maximum Range Dotted Line")
@export_range(20.0, 1000.0, 10.0, "or_greater") var dash_length_m: float = 180.0
@export_range(10.0, 1000.0, 10.0, "or_greater") var gap_length_m: float = 120.0
@export_range(1.0, 40.0, 0.5, "or_greater") var line_width_m: float = 8.0
@export_range(0.05, 10.0, 0.05, "or_greater") var sea_surface_offset_m: float = 1.0
@export_range(0.01, 0.5, 0.01, "or_greater") var refresh_interval_sec: float = 0.05
@export var line_color: Color = Color(1.0, 1.0, 1.0, 0.88)

@onready var mesh_instance: MeshInstance3D = $TrajectoryMesh

var controlled_ship: ShipUnit
var sea_level_m: float = 0.0
var _immediate_mesh := ImmediateMesh.new()
var _line_material := StandardMaterial3D.new()
var _refresh_elapsed_sec: float = 0.0


func _ready() -> void:
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.albedo_color = Color.WHITE
	_line_material.emission_enabled = true
	_line_material.emission = Color.WHITE
	_line_material.emission_energy_multiplier = 1.2
	_line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.mesh = _immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visible = false


func setup(ship: ShipUnit, water_height_m: float) -> void:
	controlled_ship = ship
	sea_level_m = water_height_m
	_redraw()


func _process(delta: float) -> void:
	_refresh_elapsed_sec += delta
	if _refresh_elapsed_sec < refresh_interval_sec:
		return
	_refresh_elapsed_sec = 0.0
	_redraw()


func _redraw() -> void:
	_immediate_mesh.clear_surfaces()
	if not is_instance_valid(controlled_ship):
		mesh_instance.visible = false
		return
	var turrets := controlled_ship.get_turrets()
	if turrets.is_empty():
		mesh_instance.visible = false
		return
	var turret := turrets[0] as Turret
	if turret == null:
		mesh_instance.visible = false
		return

	var maximum_range_m := maxf(turret.maximum_firing_range_m, 1.0)
	var origin := turret.get_muzzle_position()
	origin.y = sea_level_m + sea_surface_offset_m
	var horizontal_direction := -turret.global_transform.basis.z
	horizontal_direction.y = 0.0
	if horizontal_direction.length_squared() <= 0.000001:
		mesh_instance.visible = false
		return
	horizontal_direction = horizontal_direction.normalized()
	var side_direction := horizontal_direction.cross(Vector3.UP).normalized()
	var half_width := line_width_m * 0.5
	var dash_step := maxf(dash_length_m + gap_length_m, 1.0)
	var dash_start_m := 0.0
	var last_dash_end_m := 0.0

	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _line_material)
	while dash_start_m < maximum_range_m:
		var dash_end_m := minf(dash_start_m + dash_length_m, maximum_range_m)
		_add_dash(origin, horizontal_direction, side_direction, half_width, dash_start_m, dash_end_m)
		last_dash_end_m = dash_end_m
		dash_start_m += dash_step
	if last_dash_end_m < maximum_range_m - 0.01:
		var terminal_start_m := maxf(maximum_range_m - minf(dash_length_m, gap_length_m), 0.0)
		_add_dash(origin, horizontal_direction, side_direction, half_width, terminal_start_m, maximum_range_m)
	_immediate_mesh.surface_end()
	mesh_instance.visible = true


func _add_dash(
		origin: Vector3,
		direction: Vector3,
		side_direction: Vector3,
		half_width: float,
		start_distance_m: float,
		end_distance_m: float
) -> void:
	var start_center := origin + direction * start_distance_m
	var end_center := origin + direction * end_distance_m
	var start_left := start_center - side_direction * half_width
	var start_right := start_center + side_direction * half_width
	var end_left := end_center - side_direction * half_width
	var end_right := end_center + side_direction * half_width
	_add_colored_vertex(start_left)
	_add_colored_vertex(end_left)
	_add_colored_vertex(end_right)
	_add_colored_vertex(start_left)
	_add_colored_vertex(end_right)
	_add_colored_vertex(start_right)


func _add_colored_vertex(vertex: Vector3) -> void:
	_immediate_mesh.surface_set_color(line_color)
	_immediate_mesh.surface_add_vertex(vertex)


func has_visible_trajectory() -> bool:
	return has_visible_range_line()


func has_visible_range_line() -> bool:
	return mesh_instance.visible and _immediate_mesh.get_surface_count() > 0


func get_rendered_maximum_range_m() -> float:
	if not is_instance_valid(controlled_ship):
		return 0.0
	var turrets := controlled_ship.get_turrets()
	if turrets.is_empty():
		return 0.0
	return (turrets[0] as Turret).maximum_firing_range_m
