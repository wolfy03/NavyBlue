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


## Navigation-phase solve: approach and dive-entry geometry from the
## squadron's current state toward the resolved target.
static func build_navigation_solution(
		squadron: AircraftSquadron,
		reference_aircraft: AircraftUnit,
		resolved_target: DiveBombResolvedTarget,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		include_approach_time: bool,
		context: DiveBombAttackContext
) -> DiveBombAttackSolution:
	if resolved_target == null or not resolved_target.is_valid() \
			or dive_data == null or weapon_data == null:
		return null
	var target_position := resolved_target.get_aim_position()
	# One solve per squadron, anchored on the central reference aircraft.
	# Individual aircraft never run their own resolver.
	var solve_position := reference_aircraft.global_position \
		if reference_aircraft != null else squadron.formation_center
	var solve_forward := -reference_aircraft.global_transform.basis.z \
		if reference_aircraft != null else squadron.get_formation_forward()
	var solution := DiveBombAttackResolver.solve(
		solve_position,
		solve_forward,
		get_formation_speed_mps(squadron),
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


## Commit/lock solve anchored on the reference aircraft's real position,
## aiming at the target's future position plus the pass's deterministic
## accuracy offset. A committed dive passes its locked direction so the
## heading never wanders.
static func build_commit_solution(
		_squadron: AircraftSquadron,
		reference_aircraft: AircraftUnit,
		resolved_target: DiveBombResolvedTarget,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		context: DiveBombAttackContext,
		locked_direction: Vector3 = Vector3.ZERO
) -> DiveBombAttackSolution:
	if resolved_target == null or not resolved_target.is_valid() \
			or reference_aircraft == null or dive_data == null \
			or weapon_data == null:
		return null
	ensure_pass_dispersion(context, resolved_target, dive_data)
	var target_position := resolved_target.get_aim_position()
	var solution := DiveBombAttackResolver.solve_from_current_dive_state(
		reference_aircraft.global_position,
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
	if target_key == context.dispersion_target_key:
		return
	context.dispersion_target_key = target_key
	context.pass_dispersion_offset = dive_data.get_accuracy_profile() \
		.resolve_dispersion_offset(hash([
			context.squadron_combat_id,
			target_key,
			context.attack_pass_index,
			context.solution_revision,
		]))


## Stable identity of what the pass is aimed at: the ship instance for ship
## targets, the hashed designation for position targets.
static func get_target_identity_key(
		resolved_target: DiveBombResolvedTarget
) -> int:
	if resolved_target.is_ship_target():
		return resolved_target.ship_instance_id
	return hash(resolved_target.designated_world_position)


## Distance-gate probe shared by AI missions and player runs: the dive
## commits when the reference aircraft's horizontal distance to the intended
## impact matches the fixed trajectory's total horizontal travel.
static func evaluate_commit_gate(
		reference_position: Vector3,
		solution: DiveBombAttackSolution,
		commit_margin_m: float
) -> Dictionary:
	var required_travel := solution.horizontal_dive_distance_m \
		+ solution.bomb_horizontal_travel_m
	var to_intended := solution.intended_target_impact_position \
		- reference_position
	to_intended.y = 0.0
	var distance := to_intended.length()
	return {
		"distance_m": distance,
		"required_travel_m": required_travel,
		"should_commit": distance <= required_travel + commit_margin_m,
		"final_aim": solution.final_aim_impact_position,
		"attack_direction": solution.attack_direction,
	}


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
