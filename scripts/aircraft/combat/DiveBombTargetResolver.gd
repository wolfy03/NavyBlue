extends RefCounted
class_name DiveBombTargetResolver
## Pure dive-bomb target selection, shared by AI and player orders.
##
## Priority:
##   1. a valid explicit hostile ship (kept even outside the radius)
##   2. the hostile ship closest to the designation inside the radius
##   3. the designated world position itself (when fallback is allowed)
##   4. INVALID
##
## Stateless and pure: no SceneTree, groups, physics queries, autoloads,
## Time or global singletons. The caller injects the candidate ships, so one
## O(N) sweep per resolve is the entire cost.

const EPSILON := 0.0001


static func resolve(
		request: DiveBombTargetRequest,
		candidate_ships: Array[ShipUnit]
) -> DiveBombResolvedTarget:
	if request == null:
		return _invalid_result(null, &"missing_request")
	var explicit := request.get_explicit_target()
	if _is_attackable(request, explicit):
		return _ship_result(request, explicit, &"explicit_target")
	var acquired := _acquire_nearest_in_radius(request, candidate_ships)
	if acquired != null:
		return _ship_result(request, acquired, &"radius_acquired")
	if request.allow_position_fallback:
		return _position_result(request)
	return _invalid_result(request, &"no_target")


## XZ distance only: designation and ship live at different heights.
static func horizontal_distance_squared(
		a: Vector3,
		b: Vector3
) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


## Candidate desirability, higher is better. Currently pure proximity to the
## designation; ship-class or threat weighting slots in here later without
## touching the selection loop.
static func calculate_candidate_score(
		request: DiveBombTargetRequest,
		ship: ShipUnit
) -> float:
	return -sqrt(horizontal_distance_squared(
		request.designated_world_position,
		ship.global_position
	))


static func _acquire_nearest_in_radius(
		request: DiveBombTargetRequest,
		candidate_ships: Array[ShipUnit]
) -> ShipUnit:
	var radius := maxf(request.acquisition_radius_m, 0.0)
	if radius <= 0.0:
		return null
	var radius_squared := radius * radius
	var best: ShipUnit = null
	var best_score := -INF
	for ship in candidate_ships:
		if not _is_attackable(request, ship):
			continue
		if horizontal_distance_squared(
			request.designated_world_position,
			ship.global_position
		) > radius_squared:
			continue
		var score := calculate_candidate_score(request, ship)
		if best == null or score > best_score + EPSILON:
			best = ship
			best_score = score
		elif absf(score - best_score) <= EPSILON \
				and _breaks_tie_before(ship, best):
			best = ship
	return best


## Deterministic tie-break for equal scores: authored ship id first, then the
## stable combat identity. Runtime allocation order never affects selection.
static func _breaks_tie_before(
		candidate: ShipUnit,
		incumbent: ShipUnit
) -> bool:
	if candidate.ship_id != incumbent.ship_id:
		return candidate.ship_id < incumbent.ship_id
	return CombatIdentity.for_ship(candidate) \
		< CombatIdentity.for_ship(incumbent)


static func _is_attackable(
		request: DiveBombTargetRequest,
		ship: ShipUnit
) -> bool:
	if ship == null or not is_instance_valid(ship) \
			or ship.is_queued_for_deletion():
		return false
	if not ship.is_alive():
		return false
	if not FactionRelations.are_hostile(request.requesting_team, ship.team):
		return false
	if request.require_detected_target \
			and ship.has_method(&"is_detected_by_team") \
			and not bool(ship.call(
				&"is_detected_by_team",
				request.requesting_team
			)):
		return false
	return true


static func _ship_result(
		request: DiveBombTargetRequest,
		ship: ShipUnit,
		reason: StringName
) -> DiveBombResolvedTarget:
	var result := DiveBombResolvedTarget.new()
	result.type = DiveBombResolvedTarget.TargetType.SHIP
	result.designated_world_position = request.designated_world_position
	result.resolved_aim_position = ship.global_position
	result.target_velocity = ship.get_world_velocity()
	result.ship_ref = weakref(ship)
	result.ship_instance_id = ship.get_instance_id()
	result.target_combat_id = CombatIdentity.for_ship(ship)
	result.distance_from_designation_m = sqrt(horizontal_distance_squared(
		request.designated_world_position,
		ship.global_position
	))
	result.resolution_reason = reason
	return result


static func _position_result(
		request: DiveBombTargetRequest
) -> DiveBombResolvedTarget:
	var result := DiveBombResolvedTarget.new()
	result.type = DiveBombResolvedTarget.TargetType.WORLD_POSITION
	result.designated_world_position = request.designated_world_position
	result.resolved_aim_position = request.designated_world_position
	result.target_velocity = Vector3.ZERO
	result.resolution_reason = &"position_fallback"
	return result


static func _invalid_result(
		request: DiveBombTargetRequest,
		reason: StringName
) -> DiveBombResolvedTarget:
	var result := DiveBombResolvedTarget.new()
	result.type = DiveBombResolvedTarget.TargetType.INVALID
	if request != null:
		result.designated_world_position = request.designated_world_position
		result.resolved_aim_position = request.designated_world_position
	result.resolution_reason = reason
	return result
