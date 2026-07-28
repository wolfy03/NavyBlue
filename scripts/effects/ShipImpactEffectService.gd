extends RefCounted
class_name ShipImpactEffectService

static var _invalid_controller_warned := false


static func emit_shell_impact(
		caller: Node,
		position: Vector3,
		normal: Vector3,
		incoming_velocity: Vector3,
		result: DamageResult,
		shell_data: ShellProjectileData
) -> void:
	var controller := _get_controller(caller)
	if controller == null:
		return
	var shell_type := shell_data.shell_type \
		if shell_data != null else _get_shell_type_from_result(result)
	var base_damage := shell_data.damage if shell_data != null else 0.0
	if result != null:
		base_damage = maxf(base_damage, result.raw_damage)
	var strength := clampf(sqrt(maxf(base_damage, 1.0) / 45.0), 0.75, 4.0)
	if shell_type == ShellStats.ShellType.HE:
		strength = minf(strength * 1.25, 4.0)
	controller.call(
		&"spawn_shell_impact",
		position,
		normal,
		incoming_velocity,
		result.hit_outcome if result != null else HitOutcome.Type.NONE,
		shell_type,
		strength
	)


static func emit_torpedo_impact(
		caller: Node,
		hit_position: Vector3,
		hit_normal: Vector3,
		incoming_direction: Vector3,
		result: DamageResult,
		torpedo_data: TorpedoProjectileData,
		fallback_water_height_m: float = 0.0
) -> void:
	if caller == null or not is_instance_valid(caller):
		return
	var direct_damage := torpedo_data.direct_damage \
		if torpedo_data != null else 0.0
	var explosion_damage := torpedo_data.explosion_damage \
		if torpedo_data != null else 0.0
	var resolved_damage := result.raw_damage if result != null else 0.0
	var strength := clampf(
		maxf(direct_damage + explosion_damage, resolved_damage) / 250.0,
		1.5,
		4.0
	)
	var surface_height := WaterIntersection.get_water_height(
		caller,
		hit_position,
		fallback_water_height_m
	)
	var surface_position := Vector3(
		hit_position.x,
		surface_height,
		hit_position.z
	)
	var controller := _get_controller(caller)
	if controller != null:
		controller.call(
			&"spawn_torpedo_impact",
			hit_position,
			surface_position,
			hit_normal,
			strength
		)
	var splash_velocity := Vector3.UP * (36.0 + strength * 14.0)
	if incoming_direction.length_squared() > 0.0001:
		splash_velocity += incoming_direction.normalized() * 5.0
	WaterImpactService.emit_impact(
		caller,
		surface_position,
		clampf(strength * 1.25, 2.0, 4.0),
		splash_velocity,
		Vector3.UP
	)


static func _get_controller(caller: Node) -> Node:
	if caller == null or not is_instance_valid(caller) \
			or caller.get_tree() == null:
		return null
	var controller := caller.get_tree().get_first_node_in_group(
		&"combat_effect_controller"
	)
	if controller == null:
		return null
	if not controller.has_method(&"spawn_shell_impact") \
			or not controller.has_method(&"spawn_torpedo_impact"):
		if not _invalid_controller_warned:
			_invalid_controller_warned = true
			push_warning(
				"CombatEffectController does not expose the required impact API."
			)
		return null
	return controller


static func _get_shell_type_from_result(
		result: DamageResult
) -> ShellStats.ShellType:
	if result != null and result.damage_type == DamageType.Type.SHELL_HE:
		return ShellStats.ShellType.HE
	return ShellStats.ShellType.AP
