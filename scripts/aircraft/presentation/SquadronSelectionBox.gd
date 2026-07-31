extends Node3D
class_name SquadronSelectionBox

var settings: AircraftCommandPresentationSettings

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
	_apply_shared_material_color()


func set_bounds(bounds: AABB) -> void:
	if settings == null:
		return
	var size := bounds.size
	size.x = maxf(size.x, settings.minimum_box_size_m.x)
	size.y = maxf(size.y, settings.minimum_box_size_m.y)
	size.z = maxf(size.z, settings.minimum_box_size_m.z)
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


func calculate_squadron_bounds(
		squadron: AircraftSquadron
) -> AABB:
	var minimum_size := settings.minimum_box_size_m \
		if settings != null else Vector3(80.0, 30.0, 80.0)
	if squadron == null or not is_instance_valid(squadron):
		return AABB(Vector3.ZERO, minimum_size)
	var aircraft := squadron.get_alive_aircraft()
	if aircraft.is_empty():
		return AABB(
			squadron.formation_center - minimum_size * 0.5,
			minimum_size
		)
	var minimum := aircraft[0].global_position
	var maximum := minimum
	for unit in aircraft:
		minimum = minimum.min(unit.global_position)
		maximum = maximum.max(unit.global_position)
	var padding := settings.bounds_padding_m \
		if settings != null else Vector3.ZERO
	minimum -= padding
	maximum += padding
	return AABB(minimum, maximum - minimum)


func _apply_shared_material_color() -> void:
	if settings == null or _x_edges.is_empty():
		return
	var material := _x_edges[0].material_override \
		as StandardMaterial3D
	if material != null:
		material.albedo_color = settings.selection_color
