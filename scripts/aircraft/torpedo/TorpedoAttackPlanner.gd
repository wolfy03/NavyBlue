extends RefCounted
class_name TorpedoAttackPlanner

# Below this target speed (m/s, squared) the ship's facing is used for the beam
# axis; above it the actual velocity heading is preferred.
const MINIMUM_HEADING_SPEED_SQ := 4.0

# Fallback arming distance when the squadron's torpedo data is unavailable.
const DEFAULT_ARMING_DISTANCE_M := 50.0

# Extra distance the torpedo runs while armed before reaching the target, on top
# of its arming (safety) distance. The torpedo is released this much plus the
# arming distance short of the predicted impact point so it arms during the run
# and is live by the time it reaches the ship.
const TORPEDO_ARMED_APPROACH_MARGIN_M := 100.0

var _resolver := TorpedoAttackCommandResolver.new()
var _lead_predictor := TorpedoLeadPredictor.new()


func plan_attack(
		squadron: AircraftSquadron,
		target_ship: ShipUnit,
		battle_environment: BattleEnvironment = null,
		predict_lead: bool = false
) -> TorpedoAttackResolveResult:
	if squadron == null or not is_instance_valid(squadron):
		return TorpedoAttackResolveResult.failed(&"invalid_squadron")
	if target_ship == null or not is_instance_valid(target_ship) \
			or not target_ship.is_alive():
		return TorpedoAttackResolveResult.failed(&"invalid_target")
	var profile := squadron.get_torpedo_attack_profile()
	if profile == null:
		return TorpedoAttackResolveResult.failed(&"invalid_profile")
	var torpedo_data := _get_torpedo_data(squadron)
	# The torpedo must run a short distance before it arms and can detonate, so
	# it is released this far short of the point it should hit.
	var run_distance := _torpedo_run_distance(torpedo_data)
	# Where the torpedo should actually strike. For a moving ship this leads the
	# target; for a stationary one it is the ship's current position.
	var impact_point := target_ship.global_position
	if predict_lead:
		impact_point = _lead_predictor.predict_impact_position(
			squadron,
			target_ship,
			profile,
			run_distance,
			torpedo_data
		)
	var to_target := impact_point - squadron.formation_center
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		to_target = squadron.get_formation_forward()
		to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return TorpedoAttackResolveResult.failed(&"direction_unavailable")
	to_target = to_target.normalized()
	# Try a flank (beam) run first, then the opposite beam, then a head-on run.
	# The first geometry the resolver accepts (min distance + map bounds) wins.
	for direction in _attack_direction_candidates(target_ship, to_target):
		# The predicted position is the torpedo's IMPACT point. Drop the torpedo
		# short of it by the armed run distance so the torpedo runs onto the ship
		# instead of being dropped on top of it.
		var release_point := impact_point - direction * run_distance
		var entry_point := release_point \
			- direction * profile.minimum_attack_run_distance_m
		var result := _resolver.resolve(
			squadron,
			entry_point,
			release_point,
			profile,
			battle_environment,
			target_ship
		)
		if result.success:
			return result
	return TorpedoAttackResolveResult.failed(&"no_valid_attack_geometry")


func _get_torpedo_data(squadron: AircraftSquadron) -> TorpedoProjectileData:
	var weapon_data := squadron.get_aircraft_weapon_data()
	if weapon_data == null:
		return null
	return weapon_data.projectile_data as TorpedoProjectileData


func _torpedo_run_distance(torpedo_data: TorpedoProjectileData) -> float:
	var arming_distance := DEFAULT_ARMING_DISTANCE_M
	if torpedo_data != null:
		arming_distance = maxf(torpedo_data.arming_distance_m, 0.0)
	return arming_distance + TORPEDO_ARMED_APPROACH_MARGIN_M


func _attack_direction_candidates(
		target_ship: ShipUnit,
		head_on_direction: Vector3
) -> Array[Vector3]:
	# Prefer running perpendicular to the target's heading so torpedoes cross its
	# path. Approach from the beam nearest the squadron, fall back to the far
	# beam, then to a head-on run.
	var candidates: Array[Vector3] = []
	var target_forward := -target_ship.global_transform.basis.z
	target_forward.y = 0.0
	var target_velocity := target_ship.get_world_velocity()
	target_velocity.y = 0.0
	if target_velocity.length_squared() >= MINIMUM_HEADING_SPEED_SQ:
		target_forward = target_velocity
	var near_beam := select_beam_direction(target_forward, head_on_direction)
	if near_beam.length_squared() > 0.0001:
		candidates.append(near_beam)
		candidates.append(-near_beam)
	candidates.append(head_on_direction)
	return candidates


static func select_beam_direction(
		target_forward: Vector3,
		head_on_direction: Vector3
) -> Vector3:
	# Beam axis: perpendicular to the target heading, on the side the squadron is
	# approaching from. Returns Vector3.ZERO when the heading is degenerate.
	var forward := target_forward
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.ZERO
	forward = forward.normalized()
	var lateral := forward.cross(Vector3.UP)
	if lateral.length_squared() <= 0.0001:
		return Vector3.ZERO
	lateral = lateral.normalized()
	return lateral if lateral.dot(head_on_direction) >= 0.0 else -lateral
