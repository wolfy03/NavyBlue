@tool
extends MeshInstance3D
class_name OceanVisual

const MAX_WAVE_COUNT := 4
const DEFAULT_MATERIAL := preload("res://scripts/world/ocean/ocean_material.tres")

@export_range(32.0, 4096.0, 1.0, "or_greater") var mesh_size: float = 420.0:
	set(value):
		mesh_size = maxf(value, 1.0)
		_rebuild_mesh()

@export_range(1, 256, 1, "or_greater") var mesh_subdivisions: int = 96:
	set(value):
		mesh_subdivisions = maxi(value, 1)
		_rebuild_mesh()

@export var follow_target: Node3D:
	set(value):
		follow_target = value
		_update_process_state()

@export_node_path("Node3D") var follow_target_path: NodePath:
	set(value):
		follow_target_path = value
		_resolved_follow_target = null
		_update_process_state()

@export var auto_find_camera: bool = true:
	set(value):
		auto_find_camera = value
		_resolved_follow_target = null
		_update_process_state()

@export_range(0.1, 128.0, 0.1, "or_greater") var follow_snap_size: float = 8.0
@export var ocean_material: ShaderMaterial = DEFAULT_MATERIAL:
	set(value):
		ocean_material = value
		_apply_material()
		_apply_wave_parameters()

@export var waves: Array[Resource] = [
	preload("res://scripts/world/ocean/default_ocean_wave_data.tres"),
	preload("res://scripts/world/ocean/default_ocean_wave_cross.tres"),
	preload("res://scripts/world/ocean/default_ocean_wave_swell.tres"),
]:
	set(value):
		_disconnect_wave_signals()
		waves = value
		_connect_wave_signals()
		_apply_wave_parameters()

var _shader_time: float = 0.0
var _sea_level_y: float = 0.0
var _resolved_follow_target: Node3D
var _mesh_dirty: bool = true


func _ready() -> void:
	_sea_level_y = global_position.y
	_apply_material()
	_rebuild_mesh()
	_connect_wave_signals()
	_apply_wave_parameters()
	_update_process_state()


func _process(_delta: float) -> void:
	_follow_target_xz()


func refresh_wave_parameters() -> void:
	_apply_wave_parameters()


func set_waves(new_waves: Array[Resource]) -> void:
	waves = new_waves


func clear_waves() -> void:
	waves = []


func set_ocean_time(time_seconds: float) -> void:
	_shader_time = maxf(time_seconds, 0.0)
	_set_shader_parameter(&"ocean_time", _shader_time)


func get_ocean_time() -> float:
	return _shader_time


func get_wave_height_at_world_position(world_position: Vector3, time_seconds: float = _shader_time) -> float:
	var height := 0.0
	var wave_count := mini(waves.size(), MAX_WAVE_COUNT)
	var world_xz := Vector2(world_position.x, world_position.z)
	for index in wave_count:
		var wave: Resource = waves[index]
		if wave != null:
			height += _sample_wave_height(wave, world_xz, time_seconds)
	return height


func _apply_material() -> void:
	if ocean_material == null:
		ocean_material = DEFAULT_MATERIAL
	material_override = ocean_material


func _rebuild_mesh() -> void:
	_mesh_dirty = true
	if not is_inside_tree():
		return
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(mesh_size, mesh_size)
	plane_mesh.subdivide_width = mesh_subdivisions
	plane_mesh.subdivide_depth = mesh_subdivisions
	mesh = plane_mesh
	_mesh_dirty = false


func _apply_wave_parameters() -> void:
	if ocean_material == null:
		return

	var active_wave_count := mini(waves.size(), MAX_WAVE_COUNT)
	_set_shader_parameter(&"active_wave_count", active_wave_count)

	for index in MAX_WAVE_COUNT:
		var direction_amplitude := Vector4.ZERO
		var frequency_speed_phase := Vector4.ZERO
		if index < active_wave_count:
			var wave: Resource = waves[index]
			if wave != null:
				var direction := _get_wave_direction(wave)
				direction_amplitude = Vector4(direction.x, direction.y, _get_wave_float(wave, &"amplitude"), 0.0)
				frequency_speed_phase = Vector4(
					_get_wave_float(wave, &"frequency"),
					_get_wave_float(wave, &"speed"),
					_get_wave_float(wave, &"phase_offset"),
					0.0
				)
		_set_shader_parameter(StringName("wave_direction_amplitude_%d" % index), direction_amplitude)
		_set_shader_parameter(StringName("wave_frequency_speed_phase_%d" % index), frequency_speed_phase)


func _sample_wave_height(wave: Resource, world_xz: Vector2, time_seconds: float) -> float:
	if wave.has_method(&"sample_height"):
		return float(wave.call(&"sample_height", world_xz, time_seconds))
	var direction := _get_wave_direction(wave)
	var phase := direction.dot(world_xz) * _get_wave_float(wave, &"frequency") + time_seconds * _get_wave_float(wave, &"speed") + _get_wave_float(wave, &"phase_offset")
	return sin(phase) * _get_wave_float(wave, &"amplitude")


func _get_wave_direction(wave: Resource) -> Vector2:
	if wave.has_method(&"get_normalized_direction"):
		return wave.call(&"get_normalized_direction") as Vector2
	var direction_variant: Variant = wave.get(&"direction")
	var direction := direction_variant as Vector2
	if direction.length_squared() <= 0.000001:
		return Vector2.RIGHT
	return direction.normalized()


func _get_wave_float(wave: Resource, property_name: StringName) -> float:
	return float(wave.get(property_name))


func _follow_target_xz() -> void:
	var target := _get_follow_target()
	if target == null:
		return

	var target_position := target.global_position
	var snap_size := maxf(follow_snap_size, 0.001)
	global_position = Vector3(
		snappedf(target_position.x, snap_size),
		_sea_level_y,
		snappedf(target_position.z, snap_size)
	)


func _get_follow_target() -> Node3D:
	if is_instance_valid(follow_target):
		return follow_target
	if is_instance_valid(_resolved_follow_target):
		return _resolved_follow_target
	if follow_target_path != NodePath() and has_node(follow_target_path):
		_resolved_follow_target = get_node_or_null(follow_target_path) as Node3D
		return _resolved_follow_target
	if auto_find_camera:
		_resolved_follow_target = _find_camera()
	return _resolved_follow_target


func _find_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport != null:
		var current_camera := viewport.get_camera_3d()
		if current_camera != null:
			return current_camera

	var scene_root := get_tree().current_scene if get_tree() != null else null
	if scene_root == null:
		return null
	return _find_first_camera(scene_root)


func _find_first_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var camera := _find_first_camera(child)
		if camera != null:
			return camera
	return null


func _connect_wave_signals() -> void:
	for wave in waves:
		if wave != null and not wave.changed.is_connected(_on_wave_changed):
			wave.changed.connect(_on_wave_changed)


func _disconnect_wave_signals() -> void:
	for wave in waves:
		if wave != null and wave.changed.is_connected(_on_wave_changed):
			wave.changed.disconnect(_on_wave_changed)


func _on_wave_changed() -> void:
	_apply_wave_parameters()


func _update_process_state() -> void:
	if not is_inside_tree():
		return
	set_process(true)


func _set_shader_parameter(parameter_name: StringName, value: Variant) -> void:
	if ocean_material != null:
		ocean_material.set_shader_parameter(parameter_name, value)
