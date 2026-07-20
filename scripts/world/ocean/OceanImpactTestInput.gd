extends Node
class_name OceanImpactTestInput

@export var ocean_manager_path: NodePath = ^"../Ocean"
@export var ocean_interaction_path: NodePath = ^"../Ocean/OceanInteraction"
@export var camera_path: NodePath = ^"../Camera3D"
@export var default_impact_velocity := Vector3(0.0, -48.0, 0.0)

var _burst_count: int = 0
var _burst_strength: float = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_spawn_impact_at_screen_position(event.position, 1.2)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_spawn_impact(_get_center_surface_position(), 0.7)
			KEY_2:
				_spawn_impact(_get_center_surface_position(), 1.6)
			KEY_3:
				_spawn_impact(_get_center_surface_position(), 3.0)
			KEY_4:
				_start_burst(12, 1.2)
			KEY_5:
				_start_burst(96, 1.0)


func _process(_delta: float) -> void:
	if _burst_count <= 0:
		return
	var offset := Vector3(randf_range(-28.0, 28.0), 0.0, randf_range(-28.0, 28.0))
	_spawn_impact(_get_center_surface_position() + offset, _burst_strength)
	_burst_count -= 1


func _start_burst(count: int, strength: float) -> void:
	_burst_count = maxi(count, 0)
	_burst_strength = maxf(strength, 0.0)


func _spawn_impact_at_screen_position(screen_position: Vector2, strength: float) -> void:
	var camera := get_node_or_null(camera_path) as Camera3D
	var ocean := get_node_or_null(ocean_manager_path)
	if camera == null or ocean == null:
		return
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) <= 0.0001:
		return
	var sea_level: float = ocean.global_position.y
	var ratio: float = (sea_level - origin.y) / direction.y
	if ratio < 0.0:
		return
	var plane_point: Vector3 = origin + direction * ratio
	var surface_point: Vector3 = ocean.call(&"get_water_surface_position", plane_point)
	_spawn_impact(surface_point, strength)


func _spawn_impact(world_position: Vector3, strength: float) -> void:
	var ocean := get_node_or_null(ocean_manager_path)
	var interaction := get_node_or_null(ocean_interaction_path)
	if ocean == null or interaction == null:
		return
	var surface_position: Vector3 = ocean.call(&"get_water_surface_position", world_position)
	var surface_normal: Vector3 = ocean.call(&"get_water_normal", surface_position)
	if interaction.has_method(&"register_impact_at"):
		interaction.call(&"register_impact_at", surface_position, strength, default_impact_velocity, surface_normal)


func _get_center_surface_position() -> Vector3:
	var ocean := get_node_or_null(ocean_manager_path)
	if ocean == null:
		return Vector3.ZERO
	return ocean.call(&"get_water_surface_position", Vector3.ZERO) as Vector3
