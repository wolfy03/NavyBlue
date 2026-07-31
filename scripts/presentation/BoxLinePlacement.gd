extends RefCounted
class_name BoxLinePlacement


static func place_between(
		root: Node3D,
		mesh_instance: MeshInstance3D,
		start: Vector3,
		end: Vector3,
		thickness: float
) -> bool:
	if root == null or mesh_instance == null:
		return false
	var delta := end - start
	var length := delta.length()
	if length <= 0.001:
		mesh_instance.visible = false
		return false
	root.global_position = (start + end) * 0.5
	var up := Vector3.FORWARD \
		if absf(delta.normalized().dot(Vector3.UP)) > 0.999 \
		else Vector3.UP
	root.look_at(end, up)
	mesh_instance.position = Vector3.ZERO
	mesh_instance.rotation = Vector3.ZERO
	mesh_instance.scale = Vector3(
		maxf(thickness, 0.001),
		maxf(thickness, 0.001),
		length
	)
	mesh_instance.visible = true
	return true
