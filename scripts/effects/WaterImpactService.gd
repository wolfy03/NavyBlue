extends RefCounted
class_name WaterImpactService


static func emit_impact(
		caller: Node,
		position: Vector3,
		strength: float,
		velocity: Vector3 = Vector3.ZERO,
		normal: Vector3 = Vector3.UP
) -> void:
	if caller == null:
		return
	var tree := caller.get_tree()
	if tree != null:
		var interaction := tree.get_first_node_in_group(&"ocean_interaction")
		if interaction != null and interaction.has_method(&"register_impact_at"):
			interaction.call(
				&"register_impact_at",
				position,
				maxf(strength, 0.0),
				velocity,
				normal,
				caller
			)
	if caller.has_node("/root/EventBus"):
		caller.get_node("/root/EventBus").projectile_water_impact.emit(
			position,
			maxf(strength, 0.0)
		)
