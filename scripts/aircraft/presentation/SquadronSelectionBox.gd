extends Node3D
class_name SquadronSelectionBox

var settings: AircraftCommandPresentationSettings
var _squadron_ref: WeakRef
var _runtime_material: StandardMaterial3D
var _display_size := Vector3.ZERO
var _display_size_initialized := false

@onready var _x_edges: Array[MeshInstance3D] = [
	%EdgeX1, %EdgeX2, %EdgeX3, %EdgeX4,
]
@onready var _y_edges: Array[MeshInstance3D] = [
	%EdgeY1, %EdgeY2, %EdgeY3, %EdgeY4,
]
@onready var _z_edges: Array[MeshInstance3D] = [
	%EdgeZ1, %EdgeZ2, %EdgeZ3, %EdgeZ4,
]


func setup(next_settings: AircraftCommandPresentationSettings) -> void:
	settings = next_settings
	_create_runtime_material()


func activate(squadron: AircraftSquadron) -> void:
	_squadron_ref = weakref(squadron) \
		if squadron != null and is_instance_valid(squadron) else null
	_display_size_initialized = false
	visible = true
	set_process(false)
	set_physics_process(false)


func deactivate() -> void:
	_squadron_ref = null
	_display_size = Vector3.ZERO
	_display_size_initialized = false
	visible = false
	set_process(false)
	set_physics_process(false)


func set_bounds(bounds: AABB, delta: float = 0.0) -> void:
	if settings == null:
		return
	var size := bounds.size
	size.x = maxf(size.x, settings.minimum_box_size_m.x)
	size.y = maxf(size.y, settings.minimum_box_size_m.y)
	size.z = maxf(size.z, settings.minimum_box_size_m.z)
	if not _display_size_initialized:
		_display_size = size
		_display_size_initialized = true
	else:
		_display_size.x = _smooth_dimension(
			_display_size.x,
			size.x,
			delta
		)
		_display_size.y = _smooth_dimension(
			_display_size.y,
			size.y,
			delta
		)
		_display_size.z = _smooth_dimension(
			_display_size.z,
			size.z,
			delta
		)
	size = _display_size
	global_position = bounds.get_center()
	var half := size * 0.5
	var thickness := settings.selection_line_thickness_m
	for index in 4:
		var y_sign := -1.0 if index < 2 else 1.0
		var z_sign := -1.0 if index % 2 == 0 else 1.0
		_x_edges[index].position = Vector3(
			0.0,
			y_sign * half.y,
			z_sign * half.z
		)
		_x_edges[index].scale = Vector3(
			size.x,
			thickness,
			thickness
		)
		var x_sign := -1.0 if index < 2 else 1.0
		_y_edges[index].position = Vector3(
			x_sign * half.x,
			0.0,
			z_sign * half.z
		)
		_y_edges[index].scale = Vector3(
			thickness,
			size.y,
			thickness
		)
		var y_for_z := -1.0 if index % 2 == 0 else 1.0
		_z_edges[index].position = Vector3(
			x_sign * half.x,
			y_for_z * half.y,
			0.0
		)
		_z_edges[index].scale = Vector3(
			thickness,
			thickness,
			size.z
		)


func set_visible_state(value: bool) -> void:
	visible = value


func get_runtime_material() -> StandardMaterial3D:
	return _runtime_material


func get_display_size() -> Vector3:
	return _display_size


func _create_runtime_material() -> void:
	if settings == null or _x_edges.is_empty():
		return
	if _runtime_material == null:
		var source_material := _x_edges[0].material_override \
			as StandardMaterial3D
		if source_material != null:
			_runtime_material = source_material.duplicate() \
				as StandardMaterial3D
	if _runtime_material == null:
		return
	_runtime_material.albedo_color = settings.selection_color
	for edge in _get_all_edges():
		edge.material_override = _runtime_material


func _get_all_edges() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	result.append_array(_x_edges)
	result.append_array(_y_edges)
	result.append_array(_z_edges)
	return result


func _smooth_dimension(
		current: float,
		target: float,
		delta: float
) -> float:
	if target >= current or delta <= 0.0:
		return target
	var speed := maxf(settings.bounds_shrink_speed, 0.0)
	if speed <= 0.0:
		return target
	return lerpf(
		current,
		target,
		1.0 - exp(-speed * delta)
	)
