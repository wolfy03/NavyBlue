extends Node3D
class_name FoamPatch

signal deactivated(effect)

const FOAM_SHADER := preload("res://scripts/world/ocean/effects/foam_patch.gdshader")

@export var ocean_manager_path: NodePath
@export_range(0.01, 1.0, 0.001, "or_greater") var surface_offset: float = 0.035
@export_range(1.0, 12.0, 0.1, "or_greater") var base_lifetime: float = 4.2
@export_range(0.1, 20.0, 0.1, "or_greater") var base_radius: float = 1.0
@export_range(0.1, 40.0, 0.1, "or_greater") var final_radius: float = 5.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var active: bool = false
var last_activated_msec: int = 0
var _age: float = 0.0
var _lifetime: float = 1.0
var _start_radius: float = 1.0
var _end_radius: float = 3.0
var _base_position: Vector3 = Vector3.ZERO
var _material: ShaderMaterial
var _ocean_manager: Node


func _ready() -> void:
	_setup_mesh()
	deactivate()


func activate(world_position: Vector3, strength: float) -> void:
	active = true
	visible = true
	set_process(true)
	last_activated_msec = Time.get_ticks_msec()
	_age = 0.0
	var safe_strength := clampf(strength, 0.25, 4.0)
	_lifetime = base_lifetime + safe_strength * 0.8
	_start_radius = base_radius * (0.65 + safe_strength * 0.25)
	_end_radius = final_radius * (0.65 + safe_strength * 0.32)
	_base_position = world_position
	_update_surface_position()
	_update_visuals()


func deactivate() -> void:
	active = false
	visible = false
	set_process(false)
	scale = Vector3.ONE
	_age = 0.0
	if _material != null:
		_material.set_shader_parameter(&"alpha", 0.0)
	deactivated.emit(self)


func is_available() -> bool:
	return not active


func _process(delta: float) -> void:
	if not active:
		return
	_age += delta
	if _age >= _lifetime:
		deactivate()
		return
	_update_surface_position()
	_update_visuals()


func _setup_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	mesh_instance.mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = FOAM_SHADER
	mesh_instance.material_override = _material


func _update_surface_position() -> void:
	var manager := _get_ocean_manager()
	var next_position := _base_position
	if manager != null and manager.has_method(&"get_water_height"):
		next_position.y = float(manager.call(&"get_water_height", _base_position)) + surface_offset
	else:
		next_position.y += surface_offset
	global_position = next_position


func _update_visuals() -> void:
	var t := clampf(_age / _lifetime, 0.0, 1.0)
	var radius := lerpf(_start_radius, _end_radius, smoothstep(0.0, 1.0, t))
	scale = Vector3(radius, 1.0, radius)
	if _material != null:
		_material.set_shader_parameter(&"alpha", 0.62 * (1.0 - t))
		_material.set_shader_parameter(&"noise_offset", Vector2(_age * 0.07, -_age * 0.035))


func _get_ocean_manager() -> Node:
	if is_instance_valid(_ocean_manager):
		return _ocean_manager
	if ocean_manager_path != NodePath() and has_node(ocean_manager_path):
		_ocean_manager = get_node_or_null(ocean_manager_path)
	if _ocean_manager == null:
		_ocean_manager = get_tree().get_first_node_in_group("ocean_manager") if get_tree() != null else null
	return _ocean_manager
