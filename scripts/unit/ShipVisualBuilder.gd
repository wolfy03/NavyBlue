extends Node
class_name ShipVisualBuilder

var hull_collision: CollisionShape3D
var hull_mesh: MeshInstance3D
var bow_mesh: MeshInstance3D
var deck_mesh: MeshInstance3D
var turret_mounts: Node3D

func setup(
	next_hull_collision: CollisionShape3D,
	next_hull_mesh: MeshInstance3D,
	next_bow_mesh: MeshInstance3D,
	next_deck_mesh: MeshInstance3D,
	next_turret_mounts: Node3D
) -> void:
	hull_collision = next_hull_collision
	hull_mesh = next_hull_mesh
	bow_mesh = next_bow_mesh
	deck_mesh = next_deck_mesh
	turret_mounts = next_turret_mounts

func build(ship_data: Resource, team: StringName, team_color: Color, turret_scene: PackedScene) -> Array:
	_apply_hull_shape(ship_data)
	_apply_materials(team_color)
	return _rebuild_turrets(ship_data, team, team_color, turret_scene)

func _apply_hull_shape(ship_data: Resource) -> void:
	var hull_size: Vector3 = ship_data.hull_size

	if hull_collision.shape:
		hull_collision.shape = hull_collision.shape.duplicate()
	if hull_mesh.mesh:
		hull_mesh.mesh = hull_mesh.mesh.duplicate()
	if bow_mesh.mesh:
		bow_mesh.mesh = bow_mesh.mesh.duplicate()
	if deck_mesh.mesh:
		deck_mesh.mesh = deck_mesh.mesh.duplicate()

	var box := hull_collision.shape as BoxShape3D
	if box:
		box.size = hull_size
	hull_collision.position.y = hull_size.y * 0.5

	var hull_box := hull_mesh.mesh as BoxMesh
	if hull_box:
		hull_box.size = hull_size
	hull_mesh.position.y = hull_size.y * 0.5

	var bow_prism := bow_mesh.mesh as PrismMesh
	if bow_prism:
		bow_prism.size = Vector3(hull_size.x, hull_size.y * 0.9, hull_size.x * 1.1)
	bow_mesh.position = Vector3(0.0, hull_size.y * 0.5, -hull_size.z * 0.55)

	var deck_box := deck_mesh.mesh as BoxMesh
	if deck_box:
		deck_box.size = Vector3(hull_size.x * 0.72, 0.22, hull_size.z * 0.52)
	deck_mesh.position = Vector3(0.0, hull_size.y + 0.12, 0.12)

func _apply_materials(team_color: Color) -> void:
	hull_mesh.material_override = _make_material(team_color)
	bow_mesh.material_override = hull_mesh.material_override
	deck_mesh.material_override = _make_material(team_color.darkened(0.25))

func _rebuild_turrets(ship_data: Resource, team: StringName, team_color: Color, turret_scene: PackedScene) -> Array:
	for child in turret_mounts.get_children():
		child.queue_free()

	var turrets: Array = []
	var start_z: float = -ship_data.turret_spacing * float(ship_data.turret_count - 1) * 0.5
	for index in range(ship_data.turret_count):
		var turret = turret_scene.instantiate()
		turret.name = "Turret_%02d" % index
		turret.position = Vector3(0.0, ship_data.hull_size.y + 0.28, start_z + ship_data.turret_spacing * index)
		var turret_scale := clampf(ship_data.hull_size.x / 3.0, 5.0, 13.0)
		turret.scale = Vector3.ONE * turret_scale
		turret_mounts.add_child(turret)
		turret.setup(
			team,
			team_color,
			ship_data.shell_muzzle_velocity,
			ship_data.reload_seconds,
			ship_data.maximum_firing_range_m
		)
		turrets.append(turret)
	return turrets

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = 0.08
	return material
