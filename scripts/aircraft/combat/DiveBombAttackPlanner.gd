extends RefCounted
class_name DiveBombAttackPlanner
## Builds dive-bomb attack solutions from a resolved target.
##
## Sits between target selection (DiveBombTargetResolver) and pure ballistics
## (DiveBombAttackResolver): it extracts position/velocity from the resolved
## target, applies the accuracy profile's deterministic dispersion exactly
## once per pass, assembles the resolver inputs and stamps revisions. AI
## missions and player runs both plan through here, so neither owns solver
## argument assembly or accuracy state.

const EPSILON := 0.0001


## Per-aircraft navigation solve. The squadron may average these waypoints
## while it still owns formation movement, but no central aircraft supplies
## attack geometry for another aircraft.
static func build_aircraft_navigation_solution(
		squadron: AircraftSquadron,
		aircraft: AircraftUnit,
		resolved_target: DiveBombResolvedTarget,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		include_approach_time: bool,
		context: DiveBombAttackContext
) -> DiveBombAttackSolution:
	if aircraft == null or not is_instance_valid(aircraft) \
			or resolved_target == null or not resolved_target.is_valid() \
			or dive_data == null or weapon_data == null:
		return null
	var target_position := resolved_target.get_aim_position()
	var current_speed := aircraft.get_world_velocity().length()
	if current_speed <= 0.1:
		current_speed = get_formation_speed_mps(squadron)
	var solution := DiveBombAttackResolver.solve(
		aircraft.global_position,
		aircraft.get_forward_direction(),
		current_speed,
		target_position,
		resolved_target.get_target_velocity(),
		target_position.y,
		dive_data,
		weapon_data,
		get_world_gravity(),
		get_attack_direction(squadron, target_position),
		include_approach_time
	)
	if solution != null and solution.valid and context != null:
		solution.revision = context.next_revision()
	return solution


## Commit/lock solve for exactly one aircraft. Accuracy is pass-wide, but
## entry position, velocity, release point and dive duration are not shared.
static func build_aircraft_commit_solution(
		_squadron: AircraftSquadron,
		aircraft: AircraftUnit,
		resolved_target: DiveBombResolvedTarget,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		context: DiveBombAttackContext,
		locked_direction: Vector3 = Vector3.ZERO
) -> DiveBombAttackSolution:
	if resolved_target == null or not resolved_target.is_valid() \
			or aircraft == null or not is_instance_valid(aircraft) \
			or dive_data == null or weapon_data == null:
		return null
	ensure_pass_dispersion(context, resolved_target, dive_data)
	var target_position := resolved_target.get_aim_position()
	var solution := DiveBombAttackResolver.solve_from_current_dive_state(
		aircraft.global_position,
		target_position,
		resolved_target.get_target_velocity(),
		target_position.y,
		dive_data,
		weapon_data,
		get_world_gravity(),
		locked_direction,
		context.pass_dispersion_offset if context != null else Vector3.ZERO
	)
	if solution != null and solution.valid:
		var profile := dive_data.get_accuracy_profile()
		solution.base_accuracy = profile.base_accuracy
		solution.final_accuracy = profile.base_accuracy
		solution.dispersion_radius_m = \
			context.pass_dispersion_offset.length() \
			if context != null else 0.0
		if context != null:
			solution.revision = context.next_revision()
	return solution


## Re-solves one aircraft against the pass-wide locked impact point. This is
## what lets every aircraft share one accuracy result while retaining its own
## release point, dive duration and entry geometry.
static func build_fixed_impact_solution(
		aircraft: AircraftUnit,
		final_aim_impact_position: Vector3,
		target_velocity: Vector3,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		context: DiveBombAttackContext
) -> DiveBombAttackSolution:
	if aircraft == null or not is_instance_valid(aircraft) \
			or not final_aim_impact_position.is_finite():
		return null
	var solution := DiveBombAttackResolver.solve_from_current_dive_state(
		aircraft.global_position,
		final_aim_impact_position,
		Vector3.ZERO,
		final_aim_impact_position.y,
		dive_data,
		weapon_data,
		get_world_gravity(),
		Vector3.ZERO,
		Vector3.ZERO
	)
	if solution != null and solution.valid:
		solution.target_velocity = target_velocity
		solution.exact_intended_impact_position = final_aim_impact_position
		solution.intended_target_impact_position = final_aim_impact_position
		solution.predicted_impact_position = final_aim_impact_position
		solution.final_aim_impact_position = final_aim_impact_position
		if context != null:
			solution.revision = context.next_revision()
	return solution


## Full per-aircraft entry geometry toward a pass-wide fixed impact point.
## NORMAL_APPROACH uses this after formation split; QUICK_ATTACK deliberately
## uses build_fixed_impact_solution() from the aircraft's current state.
static func build_fixed_impact_navigation_solution(
		squadron: AircraftSquadron,
		aircraft: AircraftUnit,
		final_aim_impact_position: Vector3,
		target_velocity: Vector3,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		context: DiveBombAttackContext
) -> DiveBombAttackSolution:
	if aircraft == null or not is_instance_valid(aircraft) \
			or not final_aim_impact_position.is_finite():
		return null
	var solution := DiveBombAttackResolver.solve(
		aircraft.global_position,
		aircraft.get_forward_direction(),
		maxf(aircraft.get_world_velocity().length(), 1.0),
		final_aim_impact_position,
		Vector3.ZERO,
		final_aim_impact_position.y,
		dive_data,
		weapon_data,
		get_world_gravity(),
		get_attack_direction(squadron, final_aim_impact_position),
		false
	)
	if solution != null and solution.valid:
		solution.target_velocity = target_velocity
		solution.exact_intended_impact_position = final_aim_impact_position
		solution.intended_target_impact_position = final_aim_impact_position
		solution.predicted_impact_position = final_aim_impact_position
		solution.final_aim_impact_position = final_aim_impact_position
		if context != null:
			solution.revision = context.next_revision()
	return solution


## Rolls the pass's deterministic accuracy offset if the target identity
## changed (or nothing was rolled yet). Same target + same pass keeps the
## same offset across every repath; a target change re-rolls with a fresh
## deterministic seed.
static func ensure_pass_dispersion(
		context: DiveBombAttackContext,
		resolved_target: DiveBombResolvedTarget,
		dive_data: DiveBomberCombatData
) -> void:
	if context == null or resolved_target == null or dive_data == null:
		return
	var target_key := get_target_identity_key(resolved_target)
	if context.dispersion_target_key == target_key:
		return
	context.dispersion_target_key = target_key
	context.pass_dispersion_offset = dive_data.get_accuracy_profile() \
		.resolve_dispersion_offset(hash([
			context.squadron_combat_id,
			target_key,
			context.attack_pass_index,
		]))


## Per-pass perceived tracking point. Accuracy changes where the formation
## believes the target is, while the resolved target keeps the authoritative
## ship position and velocity for diagnostics and reacquisition.
static func resolve_tracking_aim_position(
		resolved_target: DiveBombResolvedTarget,
		context: DiveBombAttackContext
) -> Vector3:
	if resolved_target == null or not resolved_target.is_valid():
		return Vector3.ZERO
	var exact := resolved_target.get_aim_position()
	var tracked := exact + (
		context.pass_dispersion_offset if context != null else Vector3.ZERO
	)
	tracked.y = exact.y
	return tracked


## Stable identity of what the pass is aimed at: the ship instance for ship
## targets, the hashed designation for position targets.
static func get_target_identity_key(
		resolved_target: DiveBombResolvedTarget
) -> int:
	if resolved_target.is_ship_target():
		var ship := resolved_target.get_ship()
		return CombatIdentity.for_ship(ship) \
			if ship != null else resolved_target.target_combat_id
	return CombatIdentity.for_world_position(
		resolved_target.designated_world_position
	)


## Attack heading: from the owning carrier toward the aim point, falling
## back to the formation when the carrier is gone.
static func get_attack_direction(
		squadron: AircraftSquadron,
		aim_position: Vector3
) -> Vector3:
	var carrier := squadron.get_owner_carrier()
	var origin := carrier.global_position \
		if carrier != null else squadron.formation_center
	var direction := aim_position - origin
	direction.y = 0.0
	return direction.normalized() \
		if direction.length_squared() > EPSILON else Vector3.FORWARD


static func get_formation_speed_mps(squadron: AircraftSquadron) -> float:
	var velocity := squadron.get_formation_velocity() \
		if squadron.has_method(&"get_formation_velocity") else Vector3.ZERO
	var speed := velocity.length()
	if speed > 0.1:
		return speed
	var data := squadron.squadron_data.aircraft_data \
		if squadron.squadron_data != null else null
	return maxf(data.cruise_speed_mps, 1.0) if data != null else 1.0


static func get_world_gravity() -> float:
	return float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
