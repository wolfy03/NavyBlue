extends RefCounted
class_name EffectFactory

var effect_controller: CombatEffectController
var events: BattleEventPublisher


func setup(
		next_effect_controller: CombatEffectController,
		next_events: BattleEventPublisher
) -> void:
	shutdown()
	effect_controller = next_effect_controller
	events = next_events


func shutdown() -> void:
	effect_controller = null
	events = null


func spawn_water_splash(
		caller: Node,
		request: EffectRequest,
		publish_legacy_water_event := false
) -> void:
	if caller == null or request == null:
		return
	WaterImpactService.emit_impact(
		caller,
		request.position,
		request.strength,
		request.velocity,
		request.normal,
		events if publish_legacy_water_event else null
	)


func spawn_shell_impact(request: EffectRequest) -> void:
	if effect_controller == null or request == null:
		return
	var shell_data := request.projectile_data as ShellProjectileData
	var shell_type := shell_data.shell_type \
		if shell_data != null else ShellStats.ShellType.AP
	var raw_damage := shell_data.damage if shell_data != null else 0.0
	if request.damage_result != null:
		raw_damage = maxf(raw_damage, request.damage_result.raw_damage)
	var strength := clampf(sqrt(maxf(raw_damage, 1.0) / 45.0), 0.75, 4.0)
	if shell_type == ShellStats.ShellType.HE:
		strength = minf(strength * 1.25, 4.0)
	effect_controller.spawn_shell_impact(
		request.position,
		request.normal,
		request.velocity,
		request.damage_result.hit_outcome \
			if request.damage_result != null else HitOutcome.Type.NONE,
		shell_type,
		strength
	)


func spawn_torpedo_impact(
		caller: Node,
		request: EffectRequest
) -> void:
	if caller == null or request == null:
		return
	var torpedo_data := request.projectile_data as TorpedoProjectileData
	var base_damage := 0.0
	if torpedo_data != null:
		base_damage = torpedo_data.direct_damage + torpedo_data.explosion_damage
	if request.damage_result != null:
		base_damage = maxf(base_damage, request.damage_result.raw_damage)
	var strength := clampf(base_damage / 250.0, 1.5, 4.0)
	var surface_height := WaterIntersection.get_water_height(
		caller,
		request.position,
		0.0
	)
	var surface_position := Vector3(
		request.position.x,
		surface_height,
		request.position.z
	)
	if effect_controller != null:
		effect_controller.spawn_torpedo_impact(
			request.position,
			surface_position,
			request.normal,
			strength
		)
	var splash_request := EffectRequest.new()
	splash_request.position = surface_position
	splash_request.normal = Vector3.UP
	splash_request.velocity = Vector3.UP * (36.0 + strength * 14.0)
	if request.velocity.length_squared() > 0.0001:
		splash_request.velocity += request.velocity.normalized() * 5.0
	splash_request.strength = clampf(strength * 1.25, 2.0, 4.0)
	spawn_water_splash(caller, splash_request, true)


func spawn_world_impact(
		caller: Node,
		request: EffectRequest
) -> void:
	if caller == null or request == null:
		return
	WorldImpactService.emit_impact(
		caller,
		request.position,
		request.normal,
		request.velocity
	)
