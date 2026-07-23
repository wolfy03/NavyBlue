@tool
extends Node3D
class_name OceanManager

const MAX_WAVE_COUNT := 0
const MIN_SAMPLE_DISTANCE := 0.001
const MIN_INTERSECTION_DENOMINATOR := 0.00001
const WATER_SURFACE_HIT := preload("res://scripts/world/ocean/WaterSurfaceHit.gd")

@export var ocean_visual_path: NodePath = ^"OceanVisual":
	set(value):
		ocean_visual_path = value
		_ocean_visual = null

@export_range(0.001, 10.0, 0.001, "or_greater") var normal_sample_distance: float = 0.75:
	set(value):
		normal_sample_distance = maxf(value, MIN_SAMPLE_DISTANCE)

@export_range(0.0, 1.0, 0.0001, "or_greater") var surface_epsilon: float = 0.03
@export_range(1, 8, 1) var intersection_iterations: int = 4
@export_range(0.0, 8.0, 0.01, "or_greater") var ocean_time_scale: float = 1.0
@export_range(1.0, 86400.0, 1.0, "or_greater") var time_wrap_seconds: float = 3600.0
@export var debug_enabled: bool = false

var _ocean_time: float = 0.0
var _ocean_visual: MeshInstance3D
var _sea_level_y: float = 0.0


func _ready() -> void:
	_sea_level_y = global_position.y
	add_to_group("ocean_manager")
	_resolve_ocean_visual()
	_sync_visual_time()


func _process(delta: float) -> void:
	_advance_ocean_time(delta)
	_sync_visual_time()


func get_ocean_time() -> float:
	return _ocean_time


func set_ocean_time(value: float) -> void:
	_ocean_time = _wrap_time(maxf(value, 0.0))
	_sync_visual_time()


func get_water_height(world_position: Vector3) -> float:
	var waves := _get_waves()
	if waves.is_empty():
		return _sea_level_y

	var height := 0.0
	var wave_count := mini(waves.size(), MAX_WAVE_COUNT)
	var world_xz := Vector2(world_position.x, world_position.z)
	var wave_height_scale := _get_wave_height_scale()

	for index in wave_count:
		var wave: Resource = waves[index]
		if wave == null:
			continue
		height += _sample_wave_height(wave, world_xz, _ocean_time) * wave_height_scale

	height = clampf(height, -_get_maximum_displacement(), _get_maximum_displacement())
	return _sea_level_y + height


func get_water_normal(world_position: Vector3) -> Vector3:
	if _get_waves().is_empty():
		return Vector3.UP

	var distance := maxf(normal_sample_distance, MIN_SAMPLE_DISTANCE)
	var center_height := get_water_height(world_position)
	var x_position := world_position + Vector3(distance, 0.0, 0.0)
	var z_position := world_position + Vector3(0.0, 0.0, distance)
	var x_height := get_water_height(x_position)
	var z_height := get_water_height(z_position)
	var tangent_x := Vector3(distance, x_height - center_height, 0.0)
	var tangent_z := Vector3(0.0, z_height - center_height, distance)
	var normal := tangent_z.cross(tangent_x)
	if normal.length_squared() <= 0.000001:
		return Vector3.UP
	normal = normal.normalized()
	if normal.dot(Vector3.UP) < 0.0:
		normal = -normal
	return normal


func get_water_surface_position(world_position: Vector3) -> Vector3:
	return Vector3(world_position.x, get_water_height(world_position), world_position.z)


func is_underwater(world_position: Vector3) -> bool:
	# Points exactly on the surface are treated as not underwater to avoid contact jitter.
	return world_position.y < get_water_height(world_position) - surface_epsilon


func did_cross_water_surface(previous_position: Vector3, current_position: Vector3) -> bool:
	if previous_position.is_equal_approx(current_position):
		return false

	var previous_difference := _get_surface_difference(previous_position)
	var current_difference := _get_surface_difference(current_position)
	return previous_difference > surface_epsilon and current_difference <= surface_epsilon


func did_exit_water_surface(previous_position: Vector3, current_position: Vector3) -> bool:
	if previous_position.is_equal_approx(current_position):
		return false

	var previous_difference := _get_surface_difference(previous_position)
	var current_difference := _get_surface_difference(current_position)
	return previous_difference < -surface_epsilon and current_difference >= -surface_epsilon


func get_surface_intersection_hit(previous_position: Vector3, current_position: Vector3) -> RefCounted:
	if not did_cross_water_surface(previous_position, current_position):
		return WATER_SURFACE_HIT.miss()

	var previous_difference := _get_surface_difference(previous_position)
	var current_difference := _get_surface_difference(current_position)
	var denominator := previous_difference - current_difference
	if absf(denominator) <= MIN_INTERSECTION_DENOMINATOR:
		return WATER_SURFACE_HIT.miss()

	var low_ratio := 0.0
	var high_ratio := 1.0
	var ratio := clampf(previous_difference / denominator, 0.0, 1.0)

	for _iteration in intersection_iterations:
		var test_position := previous_position.lerp(current_position, ratio)
		var test_difference := _get_surface_difference(test_position)
		if test_difference > 0.0:
			low_ratio = ratio
		else:
			high_ratio = ratio
		ratio = (low_ratio + high_ratio) * 0.5

	var surface_position := previous_position.lerp(current_position, ratio)
	surface_position.y = get_water_height(surface_position)
	var normal := get_water_normal(surface_position)
	return WATER_SURFACE_HIT.from_hit(surface_position, normal, ratio)


func find_surface_intersection(previous_position: Vector3, current_position: Vector3) -> Vector3:
	var hit: RefCounted = get_surface_intersection_hit(previous_position, current_position)
	if not bool(hit.get(&"hit")):
		return Vector3.INF
	return hit.get(&"position") as Vector3


func get_ship_sample_heights(front_sample: Node3D, rear_sample: Node3D, left_sample: Node3D, right_sample: Node3D) -> Dictionary:
	return {
		"front_height": get_water_height(front_sample.global_position) if front_sample != null else _sea_level_y,
		"rear_height": get_water_height(rear_sample.global_position) if rear_sample != null else _sea_level_y,
		"left_height": get_water_height(left_sample.global_position) if left_sample != null else _sea_level_y,
		"right_height": get_water_height(right_sample.global_position) if right_sample != null else _sea_level_y,
	}


func refresh_from_visual() -> void:
	_resolve_ocean_visual()
	_sync_visual_time()


func _advance_ocean_time(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if ocean_time_scale <= 0.0:
		return
	_ocean_time = _wrap_time(_ocean_time + delta * ocean_time_scale)


func _wrap_time(value: float) -> float:
	var wrap_seconds := maxf(time_wrap_seconds, 1.0)
	if value >= wrap_seconds:
		return fmod(value, wrap_seconds)
	return value


func _sync_visual_time() -> void:
	var visual := _get_ocean_visual()
	if visual != null and visual.has_method(&"set_ocean_time"):
		visual.call(&"set_ocean_time", _ocean_time)


func _get_surface_difference(world_position: Vector3) -> float:
	return world_position.y - get_water_height(world_position)


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
	var value: Variant = wave.get(property_name)
	if value == null:
		return 0.0
	return float(value)


func _get_waves() -> Array[Resource]:
	var visual := _get_ocean_visual()
	if visual == null:
		return []
	var value: Variant = visual.get(&"waves")
	if value is Array:
		return value as Array[Resource]
	return []


func _get_wave_height_scale() -> float:
	return _get_material_float(&"wave_height_scale", 1.0)


func _get_maximum_displacement() -> float:
	return maxf(_get_material_float(&"maximum_displacement", 0.0), 0.0)


func _get_material_float(parameter_name: StringName, default_value: float) -> float:
	var material := _get_ocean_material()
	if material == null:
		return default_value
	var value: Variant = material.get_shader_parameter(parameter_name)
	if value == null:
		return default_value
	return float(value)


func _get_ocean_material() -> ShaderMaterial:
	var visual := _get_ocean_visual()
	if visual == null:
		return null
	var value: Variant = visual.get(&"ocean_material")
	if value is ShaderMaterial:
		return value as ShaderMaterial
	if visual.material_override is ShaderMaterial:
		return visual.material_override as ShaderMaterial
	return null


func _get_ocean_visual() -> MeshInstance3D:
	if is_instance_valid(_ocean_visual):
		return _ocean_visual
	return _resolve_ocean_visual()


func _resolve_ocean_visual() -> MeshInstance3D:
	if ocean_visual_path != NodePath() and has_node(ocean_visual_path):
		_ocean_visual = get_node_or_null(ocean_visual_path) as MeshInstance3D
	if _ocean_visual == null:
		_ocean_visual = find_child("OceanVisual", true, false) as MeshInstance3D
	return _ocean_visual
