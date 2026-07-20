@tool
extends Node
class_name OceanInteraction

signal water_impact_registered(impact)

const WATER_IMPACT_DATA := preload("res://scripts/world/ocean/WaterImpactData.gd")
const SHADER_MAX_RIPPLES := 16

@export var ocean_manager_path: NodePath = ^"..":
	set(value):
		ocean_manager_path = value
		_ocean_manager = null

@export var ocean_visual_path: NodePath = ^"../OceanVisual":
	set(value):
		ocean_visual_path = value
		_ocean_visual = null

@export var effect_pool_path: NodePath = ^"SplashEffectPool":
	set(value):
		effect_pool_path = value
		_effect_pool = null

@export_range(1, 16, 1) var max_ripple_count: int = 16:
	set(value):
		max_ripple_count = clampi(value, 1, SHADER_MAX_RIPPLES)
		_resize_ripple_buffers()

@export_range(0.1, 20.0, 0.1, "or_greater") var ripple_lifetime: float = 5.0
@export_range(0.1, 40.0, 0.1, "or_greater") var ripple_speed: float = 8.5
@export_range(0.05, 8.0, 0.01, "or_greater") var ripple_width: float = 1.15
@export_range(0.1, 30.0, 0.1, "or_greater") var ripple_frequency: float = 7.0
@export_range(0.0, 8.0, 0.01, "or_greater") var ripple_decay: float = 1.25
@export_range(0.0, 4.0, 0.01, "or_greater") var ripple_height_scale: float = 0.35
@export_range(0.0, 4.0, 0.01, "or_greater") var impact_depression_strength: float = 0.22
@export_range(0.01, 2.0, 0.01, "or_greater") var impact_depression_duration: float = 0.28
@export_range(0.0, 8.0, 0.01, "or_greater") var maximum_impact_displacement: float = 1.4

@export var skip_ripples_beyond_camera_distance: bool = false
@export_range(1.0, 4000.0, 1.0, "or_greater") var max_ripple_camera_distance: float = 900.0

var _ocean_manager: Node
var _ocean_visual: MeshInstance3D
var _effect_pool: Node
var _ripple_data := PackedVector4Array()
var _shader_ripple_data := PackedVector4Array()
var _ripple_active: Array[bool] = []
var _ripple_write_index: int = 0
var _active_ripple_count: int = 0
var _last_ocean_time: float = 0.0


func _ready() -> void:
	add_to_group("ocean_interaction")
	_resize_ripple_buffers()
	_apply_shader_parameters()
	_update_shader_ripples(true)
	set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var ocean_time := _get_ocean_time()
	if ocean_time < _last_ocean_time:
		_clear_ripples()
	_last_ocean_time = ocean_time
	if _active_ripple_count > 0:
		_expire_old_ripples(ocean_time)
		_update_shader_ripples(false)


func register_impact(impact) -> void:
	if impact == null:
		return

	impact.set(&"impact_time", _get_ocean_time())
	water_impact_registered.emit(impact)

	var position: Vector3 = impact.get(&"world_position")
	var strength: float = maxf(float(impact.get(&"impact_strength")), 0.0)
	var velocity: Vector3 = impact.get(&"impact_velocity")
	var normal: Vector3 = impact.get(&"surface_normal")

	var pool := _get_effect_pool()
	if pool != null:
		if pool.has_method(&"spawn_splash"):
			pool.call(&"spawn_splash", position, strength, velocity, normal)
		if pool.has_method(&"spawn_foam"):
			pool.call(&"spawn_foam", position, strength)

	if _should_register_ripple(position):
		_register_ripple(position, strength, _get_ocean_time())


func register_impact_at(
		world_position: Vector3,
		strength: float,
		impact_velocity: Vector3 = Vector3.ZERO,
		surface_normal: Vector3 = Vector3.UP,
		projectile: Object = null
) -> void:
	var impact = WATER_IMPACT_DATA.new()
	impact.setup(world_position, surface_normal, impact_velocity, strength, _get_ocean_time(), projectile)
	register_impact(impact)


func get_active_ripple_count() -> int:
	return _active_ripple_count


func get_pool_debug_state() -> Dictionary:
	var pool := _get_effect_pool()
	if pool == null or not pool.has_method(&"get_debug_state"):
		return {}
	return pool.call(&"get_debug_state") as Dictionary


func refresh_shader_parameters() -> void:
	_apply_shader_parameters()
	_update_shader_ripples(true)


func _register_ripple(world_position: Vector3, strength: float, start_time: float) -> void:
	var slot := _ripple_write_index
	_ripple_write_index = (_ripple_write_index + 1) % max_ripple_count
	_ripple_data[slot] = Vector4(world_position.x, world_position.z, start_time, maxf(strength, 0.0))
	if not _ripple_active[slot]:
		_active_ripple_count += 1
	_ripple_active[slot] = true
	_update_shader_ripples(true)


func _expire_old_ripples(ocean_time: float) -> void:
	var changed := false
	for index in max_ripple_count:
		if not _ripple_active[index]:
			continue
		var start_time := _ripple_data[index].z
		var age := ocean_time - start_time
		if age < 0.0 or age > ripple_lifetime:
			_ripple_active[index] = false
			_active_ripple_count = maxi(_active_ripple_count - 1, 0)
			changed = true
	if changed:
		_update_shader_ripples(true)


func _update_shader_ripples(_force: bool) -> void:
	var material := _get_ocean_material()
	if material == null:
		return

	var shader_index := 0
	for index in max_ripple_count:
		if not _ripple_active[index]:
			continue
		_shader_ripple_data[shader_index] = _ripple_data[index]
		shader_index += 1

	for index in range(shader_index, SHADER_MAX_RIPPLES):
		_shader_ripple_data[index] = Vector4.ZERO

	material.set_shader_parameter(&"impact_ripples", _shader_ripple_data)
	material.set_shader_parameter(&"active_impact_count", shader_index)


func _clear_ripples() -> void:
	for index in SHADER_MAX_RIPPLES:
		_ripple_data[index] = Vector4.ZERO
		_shader_ripple_data[index] = Vector4.ZERO
	for index in _ripple_active.size():
		_ripple_active[index] = false
	_active_ripple_count = 0
	_ripple_write_index = 0
	_update_shader_ripples(true)


func _resize_ripple_buffers() -> void:
	if max_ripple_count <= 0:
		max_ripple_count = SHADER_MAX_RIPPLES

	_ripple_data.resize(SHADER_MAX_RIPPLES)
	_shader_ripple_data.resize(SHADER_MAX_RIPPLES)
	for index in SHADER_MAX_RIPPLES:
		_ripple_data[index] = Vector4.ZERO
		_shader_ripple_data[index] = Vector4.ZERO

	_ripple_active.clear()
	for _index in max_ripple_count:
		_ripple_active.append(false)
	_active_ripple_count = 0
	_ripple_write_index = 0


func _apply_shader_parameters() -> void:
	var material := _get_ocean_material()
	if material == null:
		return
	material.set_shader_parameter(&"ripple_speed", ripple_speed)
	material.set_shader_parameter(&"ripple_width", ripple_width)
	material.set_shader_parameter(&"ripple_frequency", ripple_frequency)
	material.set_shader_parameter(&"ripple_decay", ripple_decay)
	material.set_shader_parameter(&"ripple_height_scale", ripple_height_scale)
	material.set_shader_parameter(&"impact_depression_strength", impact_depression_strength)
	material.set_shader_parameter(&"impact_depression_duration", impact_depression_duration)
	material.set_shader_parameter(&"maximum_impact_displacement", maximum_impact_displacement)


func _should_register_ripple(world_position: Vector3) -> bool:
	if not skip_ripples_beyond_camera_distance:
		return true
	var viewport := get_viewport()
	if viewport == null:
		return true
	var camera := viewport.get_camera_3d()
	if camera == null:
		return true
	return camera.global_position.distance_to(world_position) <= max_ripple_camera_distance


func _get_ocean_time() -> float:
	var manager := _get_ocean_manager()
	if manager != null and manager.has_method(&"get_ocean_time"):
		return float(manager.call(&"get_ocean_time"))
	return 0.0


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


func _get_ocean_manager() -> Node:
	if is_instance_valid(_ocean_manager):
		return _ocean_manager
	if ocean_manager_path != NodePath() and has_node(ocean_manager_path):
		_ocean_manager = get_node_or_null(ocean_manager_path)
	return _ocean_manager


func _get_ocean_visual() -> MeshInstance3D:
	if is_instance_valid(_ocean_visual):
		return _ocean_visual
	if ocean_visual_path != NodePath() and has_node(ocean_visual_path):
		_ocean_visual = get_node_or_null(ocean_visual_path) as MeshInstance3D
	return _ocean_visual


func _get_effect_pool() -> Node:
	if is_instance_valid(_effect_pool):
		return _effect_pool
	if effect_pool_path != NodePath() and has_node(effect_pool_path):
		_effect_pool = get_node_or_null(effect_pool_path)
	return _effect_pool
