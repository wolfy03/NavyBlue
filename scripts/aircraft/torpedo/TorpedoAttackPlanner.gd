extends RefCounted
class_name TorpedoAttackPlanner

var _resolver := TorpedoAttackCommandResolver.new()


func plan_attack(
		squadron: AircraftSquadron,
		target_ship: ShipUnit,
		battle_environment: BattleEnvironment = null
) -> TorpedoAttackResolveResult:
	if squadron == null or not is_instance_valid(squadron):
		return TorpedoAttackResolveResult.failed(&"invalid_squadron")
	if target_ship == null or not is_instance_valid(target_ship) \
			or not target_ship.is_alive():
		return TorpedoAttackResolveResult.failed(&"invalid_target")
	var profile := squadron.get_torpedo_attack_profile()
	if profile == null:
		return TorpedoAttackResolveResult.failed(&"invalid_profile")
	var release_point := target_ship.global_position
	var direction := release_point - squadron.formation_center
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = squadron.get_formation_forward()
		direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return TorpedoAttackResolveResult.failed(&"direction_unavailable")
	direction = direction.normalized()
	var entry_point := release_point \
		- direction * profile.minimum_attack_run_distance_m
	return _resolver.resolve(
		squadron,
		entry_point,
		release_point,
		profile,
		battle_environment,
		target_ship
	)
