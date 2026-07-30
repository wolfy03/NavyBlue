extends Node
class_name CombatEffectPresenter

var effect_factory := EffectFactory.new()
var events: BattleEventPublisher


func setup(
		effect_controller: CombatEffectController,
		next_events: BattleEventPublisher
) -> void:
	shutdown()
	events = next_events
	effect_factory.setup(effect_controller, events)
	if events != null and not events.projectile_impact.is_connected(
		present_projectile_impact
	):
		events.projectile_impact.connect(present_projectile_impact)


func shutdown() -> void:
	if events != null and events.projectile_impact.is_connected(
		present_projectile_impact
	):
		events.projectile_impact.disconnect(present_projectile_impact)
	effect_factory.shutdown()
	events = null


func _exit_tree() -> void:
	shutdown()


func present_projectile_impact(result: ProjectileImpactResult) -> void:
	if result == null or result.projectile == null:
		return
	var request := EffectRequest.new()
	request.position = result.hit_position
	request.normal = result.hit_normal
	request.velocity = result.incoming_velocity
	request.strength = result.impact_strength
	request.damage_result = result.damage_result
	request.projectile_data = result.projectile.projectile_data
	match result.surface_type:
		ProjectileImpactResult.SurfaceType.WATER:
			effect_factory.spawn_water_splash(result.projectile, request)
		ProjectileImpactResult.SurfaceType.SHIP:
			if request.projectile_data is TorpedoProjectileData:
				effect_factory.spawn_torpedo_impact(
					result.projectile,
					request
				)
			else:
				effect_factory.spawn_shell_impact(request)
		ProjectileImpactResult.SurfaceType.TERRAIN:
			effect_factory.spawn_world_impact(result.projectile, request)
