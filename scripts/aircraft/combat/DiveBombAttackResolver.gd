extends RefCounted
class_name DiveBombAttackResolver
## Solves a dive-bombing attack backwards from the bomb's impact point.
##
## Order of reasoning (never "add more lead time"):
##   1. assume an impact point
##   2. bomb fall time at the release altitude  -> bomb horizontal travel
##   3. release point = impact - bomb travel
##   4. dive time from entry to release altitude -> aircraft horizontal travel
##   5. dive entry point = release - dive travel
##   6. approach point   = entry - approach distance
##   7. re-predict the impact from the total time and repeat
##
## Stateless and pure: no Node, SceneTree, Time or singleton access, so it is
## directly unit-testable and cheap enough to call on a repath interval.

const EPSILON := 0.0001
const DEFAULT_ITERATIONS := 4
const MAXIMUM_TOTAL_TIME_SEC := 120.0
## Below this the target counts as stationary, so a drifting velocity cannot
## make a parked ship's solution wander.
const STATIONARY_SPEED_MPS := 0.1


static func solve(
		aircraft_position: Vector3,
		aircraft_forward: Vector3,
		aircraft_speed_mps: float,
		target_position: Vector3,
		target_velocity: Vector3,
		target_world_y: float,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		gravity_mps2: float,
		attack_direction_override: Vector3 = Vector3.ZERO,
		include_approach_time: bool = true,
		iterations: int = DEFAULT_ITERATIONS
) -> DiveBombAttackSolution:
	var validation := _validate_inputs(
		aircraft_position,
		target_position,
		dive_data,
		weapon_data,
		gravity_mps2
	)
	if not validation.is_empty():
		return DiveBombAttackSolution.failed(validation)
	var attack_direction := _resolve_attack_direction(
		attack_direction_override,
		target_position,
		aircraft_position,
		aircraft_forward
	)
	if attack_direction == Vector3.ZERO:
		return DiveBombAttackSolution.failed(&"invalid_attack_direction")
	var flat_target_velocity := target_velocity
	flat_target_velocity.y = 0.0
	if flat_target_velocity.length() < STATIONARY_SPEED_MPS:
		flat_target_velocity = Vector3.ZERO
	var release_altitude := maxf(dive_data.automatic_release_altitude_m, 0.0)
	var entry_altitude := maxf(dive_data.dive_entry_altitude_m, 0.0)
	if release_altitude <= 0.0:
		return DiveBombAttackSolution.failed(&"invalid_release_altitude")
	if entry_altitude <= release_altitude:
		return DiveBombAttackSolution.failed(&"invalid_dive_geometry")
	var dive_speed := maxf(dive_data.dive_speed_mps, 0.0)
	if dive_speed <= EPSILON:
		return DiveBombAttackSolution.failed(&"invalid_dive_speed")
	var bomb_gravity := DiveBombBallistics.resolve_bomb_gravity(
		weapon_data,
		gravity_mps2
	)
	if bomb_gravity <= EPSILON:
		return DiveBombAttackSolution.failed(&"invalid_gravity")

	var dive_angle_rad := deg_to_rad(clampf(
		dive_data.dive_angle_degrees,
		1.0,
		89.0
	))
	var dive_vertical_speed := dive_speed * sin(dive_angle_rad)
	var dive_horizontal_speed := dive_speed * cos(dive_angle_rad)
	if dive_vertical_speed <= EPSILON:
		return DiveBombAttackSolution.failed(&"invalid_dive_geometry")
	# The authored entry altitude is a minimum. Ensure the solved path contains
	# enough physical dive time to satisfy the same release gate used by each
	# aircraft controller, otherwise a shallow test/profile configuration could
	# make release impossible before the safety altitude.
	entry_altitude = maxf(
		entry_altitude,
		release_altitude + dive_vertical_speed \
			* maxf(dive_data.minimum_dive_time_before_release_sec, 0.0)
	)

	# The bomb leaves with the aircraft's dive velocity, so its horizontal
	# component is the dive's horizontal component along the attack heading.
	var aircraft_release_velocity := (
		attack_direction * dive_horizontal_speed
		+ Vector3.DOWN * dive_vertical_speed
	)
	var bomb_velocity := DiveBombBallistics.resolve_bomb_initial_velocity(
		aircraft_release_velocity,
		weapon_data
	)
	var bomb_fall_time := DiveBombBallistics.solve_fall_time(
		release_altitude,
		bomb_velocity.y,
		bomb_gravity
	)
	if bomb_fall_time < 0.0:
		return DiveBombAttackSolution.failed(&"invalid_bomb_ballistics")
	var bomb_horizontal_velocity := Vector3(
		bomb_velocity.x,
		0.0,
		bomb_velocity.z
	)
	var bomb_travel := bomb_horizontal_velocity * bomb_fall_time
	var vertical_drop := entry_altitude - release_altitude
	var dive_time := vertical_drop / dive_vertical_speed
	var dive_travel := attack_direction * (dive_horizontal_speed * dive_time)
	# release_interval_sec is the stagger between bombs of one squadron, not
	# a mechanical fuse: the pass-wide solution is planned for the first bomb,
	# so no release delay enters the ballistic timing.
	var release_delay := 0.0
	var approach_distance := maxf(dive_data.approach_distance_m, 0.0)

	# Iterate: the impact point sets the total flight time, which moves the
	# impact point. Converges in a few passes for constant-velocity targets.
	var predicted_impact := target_position
	predicted_impact.y = target_world_y
	var approach_time := 0.0
	var iteration_count := 0
	var total_time := 0.0
	for _iteration in maxi(iterations, 1):
		iteration_count += 1
		var release_position := predicted_impact - bomb_travel
		release_position.y = target_world_y + release_altitude
		var entry_position := release_position - dive_travel
		entry_position.y = target_world_y + entry_altitude
		approach_time = 0.0
		if include_approach_time and aircraft_speed_mps > EPSILON:
			approach_time = aircraft_position.distance_to(entry_position) \
				/ aircraft_speed_mps
		total_time = approach_time + dive_time + release_delay + bomb_fall_time
		if total_time > MAXIMUM_TOTAL_TIME_SEC:
			return DiveBombAttackSolution.failed(&"invalid_dive_geometry")
		var next_impact := target_position + flat_target_velocity * total_time
		next_impact.y = target_world_y
		if next_impact.distance_to(predicted_impact) <= 1.0:
			predicted_impact = next_impact
			break
		predicted_impact = next_impact

	var solution := DiveBombAttackSolution.new()
	solution.target_position_at_solve = target_position
	solution.target_velocity = flat_target_velocity
	solution.attack_direction = attack_direction
	solution.intended_target_impact_position = predicted_impact
	solution.exact_intended_impact_position = predicted_impact
	solution.final_aim_impact_position = predicted_impact
	# The release point is derived from the impact, so the solved trajectory
	# lands on the intended point by construction here.
	solution.trajectory_predicted_impact_position = predicted_impact
	solution.predicted_impact_position = predicted_impact
	solution.release_position = predicted_impact - bomb_travel
	solution.release_position.y = target_world_y + release_altitude
	solution.dive_entry_position = solution.release_position - dive_travel
	solution.dive_entry_position.y = target_world_y + entry_altitude
	solution.approach_position = solution.dive_entry_position \
		- attack_direction * approach_distance
	solution.approach_position.y = target_world_y + entry_altitude
	solution.approach_time_sec = approach_time
	solution.dive_time_to_release_sec = dive_time
	solution.bomb_fall_time_sec = bomb_fall_time
	solution.release_delay_sec = release_delay
	solution.total_time_to_impact_sec = total_time
	solution.release_altitude_m = release_altitude
	solution.dive_entry_altitude_m = entry_altitude
	solution.horizontal_dive_distance_m = dive_travel.length()
	solution.bomb_horizontal_travel_m = bomb_travel.length()
	solution.predicted_bomb_velocity = bomb_velocity
	solution.solution_iteration_count = iteration_count
	if not _is_finite_solution(solution):
		return DiveBombAttackSolution.failed(&"non_finite_solution")
	solution.valid = true
	return solution


## Lock-time solve anchored on the reference aircraft's real position.
##
## Two impact points are returned and MUST stay distinct:
##   intended_target_impact_position  - target future position at bomb impact
##                                      (target lead only, computed from the
##                                      remaining dive + fall time; §7)
##   trajectory_predicted_impact_position - where the bomb lands if the fixed
##                                      dive proceeds from here
## The attack direction is aimed AT the intended point (unless a locked
## direction is supplied), so with correct entry geometry the two coincide;
## the release window then verifies their real difference instead of
## comparing a projection against itself.
static func solve_from_current_dive_state(
		reference_position: Vector3,
		target_position: Vector3,
		target_velocity: Vector3,
		target_world_y: float,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		gravity_mps2: float,
		locked_attack_direction: Vector3 = Vector3.ZERO,
		aim_offset: Vector3 = Vector3.ZERO
) -> DiveBombAttackSolution:
	var validation := _validate_inputs(
		reference_position,
		target_position,
		dive_data,
		weapon_data,
		gravity_mps2
	)
	if not validation.is_empty():
		return DiveBombAttackSolution.failed(validation)
	var release_altitude := maxf(dive_data.automatic_release_altitude_m, 0.0)
	var dive_speed := maxf(dive_data.dive_speed_mps, 0.0)
	if dive_speed <= EPSILON:
		return DiveBombAttackSolution.failed(&"invalid_dive_speed")
	var reference_altitude := reference_position.y - target_world_y
	if reference_altitude <= release_altitude:
		return DiveBombAttackSolution.failed(&"invalid_dive_geometry")
	var bomb_gravity := DiveBombBallistics.resolve_bomb_gravity(
		weapon_data,
		gravity_mps2
	)
	if bomb_gravity <= EPSILON:
		return DiveBombAttackSolution.failed(&"invalid_gravity")
	var dive_angle_rad := deg_to_rad(clampf(
		dive_data.dive_angle_degrees,
		1.0,
		89.0
	))
	var dive_vertical_speed := dive_speed * sin(dive_angle_rad)
	var dive_horizontal_speed := dive_speed * cos(dive_angle_rad)
	if dive_vertical_speed <= EPSILON:
		return DiveBombAttackSolution.failed(&"invalid_dive_geometry")
	var dive_time := (reference_altitude - release_altitude) \
		/ dive_vertical_speed
	# §7 DIVING: remaining dive time + fall time, nothing else. The fall time
	# does not depend on heading, so the intended point is exact before the
	# direction is chosen.
	var probe_bomb_velocity := DiveBombBallistics \
		.resolve_bomb_initial_velocity(
			Vector3.FORWARD * dive_horizontal_speed
				+ Vector3.DOWN * dive_vertical_speed,
			weapon_data
		)
	var bomb_fall_time := DiveBombBallistics.solve_fall_time(
		release_altitude,
		probe_bomb_velocity.y,
		bomb_gravity
	)
	if bomb_fall_time < 0.0:
		return DiveBombAttackSolution.failed(&"invalid_bomb_ballistics")
	var flat_target_velocity := target_velocity
	flat_target_velocity.y = 0.0
	if flat_target_velocity.length() < STATIONARY_SPEED_MPS:
		flat_target_velocity = Vector3.ZERO
	var exact_intended := target_position \
		+ flat_target_velocity * (dive_time + bomb_fall_time)
	exact_intended.y = target_world_y
	# The deliberate accuracy offset moves only the aim, never the physics.
	var final_aim := exact_intended + aim_offset
	final_aim.y = target_world_y
	# Aim the dive at the point we are trying to hit; a pre-locked direction
	# (already committed dive) keeps its heading.
	var attack_direction := _resolve_attack_direction(
		locked_attack_direction,
		final_aim,
		reference_position,
		Vector3.ZERO
	)
	if attack_direction == Vector3.ZERO:
		return DiveBombAttackSolution.failed(&"invalid_attack_direction")
	var release_position := reference_position \
		+ attack_direction * (dive_horizontal_speed * dive_time)
	release_position.y = target_world_y + release_altitude
	var bomb_velocity := DiveBombBallistics.resolve_bomb_initial_velocity(
		attack_direction * dive_horizontal_speed
			+ Vector3.DOWN * dive_vertical_speed,
		weapon_data
	)
	var bomb_travel := Vector3(bomb_velocity.x, 0.0, bomb_velocity.z) \
		* bomb_fall_time
	var trajectory_impact := release_position + bomb_travel
	trajectory_impact.y = target_world_y
	var solution := DiveBombAttackSolution.new()
	solution.target_position_at_solve = target_position
	solution.target_velocity = flat_target_velocity
	solution.attack_direction = attack_direction
	solution.exact_intended_impact_position = exact_intended
	solution.dispersion_offset = aim_offset
	solution.final_aim_impact_position = final_aim
	solution.intended_target_impact_position = final_aim
	solution.trajectory_predicted_impact_position = trajectory_impact
	solution.predicted_impact_position = final_aim
	solution.release_position = release_position
	solution.dive_entry_position = reference_position
	solution.approach_position = reference_position
	solution.dive_time_to_release_sec = dive_time
	solution.bomb_fall_time_sec = bomb_fall_time
	solution.total_time_to_impact_sec = dive_time + bomb_fall_time
	solution.release_altitude_m = release_altitude
	solution.dive_entry_altitude_m = reference_altitude
	solution.horizontal_dive_distance_m = dive_horizontal_speed * dive_time
	solution.bomb_horizontal_travel_m = bomb_travel.length()
	solution.predicted_bomb_velocity = bomb_velocity
	solution.solution_iteration_count = 1
	if not _is_finite_solution(solution):
		return DiveBombAttackSolution.failed(&"non_finite_solution")
	solution.valid = true
	return solution


## Convenience wrapper for a squadron already at its dive entry: the approach
## leg no longer contributes to the target's travel time.
static func solve_from_dive_entry(
		aircraft_position: Vector3,
		aircraft_forward: Vector3,
		target_position: Vector3,
		target_velocity: Vector3,
		target_world_y: float,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		gravity_mps2: float,
		attack_direction_override: Vector3 = Vector3.ZERO
) -> DiveBombAttackSolution:
	return solve(
		aircraft_position,
		aircraft_forward,
		0.0,
		target_position,
		target_velocity,
		target_world_y,
		dive_data,
		weapon_data,
		gravity_mps2,
		attack_direction_override,
		false
	)


static func _validate_inputs(
		aircraft_position: Vector3,
		target_position: Vector3,
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData,
		gravity_mps2: float
) -> StringName:
	if dive_data == null:
		return &"missing_dive_data"
	if weapon_data == null:
		return &"missing_weapon_data"
	if gravity_mps2 <= 0.0 or is_nan(gravity_mps2) or is_inf(gravity_mps2):
		return &"invalid_gravity"
	if not aircraft_position.is_finite() or not target_position.is_finite():
		return &"non_finite_solution"
	return &""


## Deterministic accuracy dispersion: one aim offset per attack pass, uniform
## on a horizontal disc whose radius shrinks linearly from the maximum (at
## accuracy 0) to the minimum (at accuracy 1). Pure function of its inputs -
## no global RNG, time or frame state - so a given squadron/target/pass seed
## always produces the same offset. The offset moves only the AIM point; the
## ballistic solution itself is never degraded.
static func resolve_accuracy_dispersion_offset(
		accuracy: float,
		minimum_radius_m: float,
		maximum_radius_m: float,
		deterministic_seed: int
) -> Vector3:
	return DiveBombAccuracyMath.resolve_offset(
		accuracy,
		minimum_radius_m,
		maximum_radius_m,
		deterministic_seed
	)


static func _resolve_attack_direction(
		override_direction: Vector3,
		target_position: Vector3,
		aircraft_position: Vector3,
		aircraft_forward: Vector3
) -> Vector3:
	var candidates: Array[Vector3] = [
		override_direction,
		target_position - aircraft_position,
		aircraft_forward,
	]
	for candidate in candidates:
		var flat := candidate
		flat.y = 0.0
		if flat.is_finite() and flat.length_squared() > EPSILON:
			return flat.normalized()
	return Vector3.ZERO


static func _is_finite_solution(
		solution: DiveBombAttackSolution
) -> bool:
	return solution.predicted_impact_position.is_finite() \
		and solution.release_position.is_finite() \
		and solution.dive_entry_position.is_finite() \
		and solution.approach_position.is_finite() \
		and is_finite(solution.total_time_to_impact_sec) \
		and is_finite(solution.bomb_fall_time_sec) \
		and is_finite(solution.dive_time_to_release_sec)


static func is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
