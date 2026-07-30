extends RefCounted
class_name WaterImpactService

static var _invalid_interaction_warned := false


static func emit_impact(
		caller: Node,
		position: Vector3,
		strength: float,
		velocity: Vector3 = Vector3.ZERO,
		normal: Vector3 = Vector3.UP,
		events: BattleEventPublisher = null
) -> void:
	if caller == null:
		return
	var tree := caller.get_tree()
	if tree != null:
		var interaction := tree.get_first_node_in_group(&"ocean_interaction")
		if interaction != null \
				and not interaction.has_method(&"register_impact_at"):
			if not _invalid_interaction_warned:
				_invalid_interaction_warned = true
				push_warning(
					"OceanInteraction does not implement register_impact_at()."
				)
		elif interaction != null:
			interaction.call(
				&"register_impact_at",
				position,
				maxf(strength, 0.0),
				velocity,
				normal,
				caller
			)
	if events != null:
		events.emit_projectile_water_impact(
			position,
			maxf(strength, 0.0)
		)
