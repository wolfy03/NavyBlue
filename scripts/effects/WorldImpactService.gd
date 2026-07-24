extends RefCounted
class_name WorldImpactService


static func emit_impact(
		caller: Node,
		position: Vector3,
		normal: Vector3,
		incoming_velocity: Vector3
) -> void:
	if caller == null or caller.get_tree() == null:
		return
	var parent := caller.get_tree().current_scene
	if parent == null:
		parent = caller.get_tree().root
	var particles := GPUParticles3D.new()
	particles.name = "ShellWorldImpact"
	particles.add_to_group(&"world_impact_effect")
	particles.one_shot = true
	particles.amount = 10
	particles.lifetime = 0.35
	particles.explosiveness = 1.0
	particles.finished.connect(particles.queue_free, CONNECT_ONE_SHOT)

	var direction := normal.normalized()
	if direction.length_squared() <= 0.000001:
		direction = -incoming_velocity.normalized()
	if direction.length_squared() <= 0.000001:
		direction = Vector3.UP
	var material := ParticleProcessMaterial.new()
	material.direction = direction
	material.spread = 35.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 8.0
	material.gravity = Vector3.DOWN * 9.8
	material.scale_min = 0.08
	material.scale_max = 0.18
	material.color = Color(0.82, 0.68, 0.48, 0.9)
	particles.process_material = material

	var fragment_mesh := BoxMesh.new()
	fragment_mesh.size = Vector3(0.08, 0.08, 0.16)
	var fragment_material := StandardMaterial3D.new()
	fragment_material.albedo_color = Color(0.72, 0.58, 0.4)
	fragment_material.roughness = 0.9
	fragment_mesh.material = fragment_material
	particles.draw_pass_1 = fragment_mesh

	parent.add_child(particles)
	particles.global_position = position
	particles.emitting = true
