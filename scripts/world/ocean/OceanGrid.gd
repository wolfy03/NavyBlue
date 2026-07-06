extends Node3D
class_name OceanGrid

@export var half_extent := 120.0
@export var spacing := 12.0
@export var line_height := 0.012
@export var line_color := Color(0.55, 0.85, 1.0, 0.18)

func _ready() -> void:
	_build_grid()

func _build_grid() -> void:
	for child in get_children():
		child.queue_free()

	var count := int(floor(half_extent / spacing))
	for i in range(-count, count + 1):
		_add_line(Vector3(i * spacing, line_height, -half_extent), Vector3(i * spacing, line_height, half_extent))
		_add_line(Vector3(-half_extent, line_height, i * spacing), Vector3(half_extent, line_height, i * spacing))

func _add_line(from: Vector3, to: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate.surface_add_vertex(from)
	immediate.surface_add_vertex(to)
	immediate.surface_end()
	mesh_instance.mesh = immediate

	var material := StandardMaterial3D.new()
	material.albedo_color = line_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.material_override = material
	add_child(mesh_instance)

