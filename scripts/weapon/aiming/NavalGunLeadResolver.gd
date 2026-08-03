extends RefCounted
class_name NavalGunLeadResolver
## Ideal (error-free) moving-target prediction for naval gunfire.
##
## Reuses BallisticMath so the predicted flight time matches the low-arc
## elevation CannonMount applies when it aims. The resolver never adds
## accuracy error; GunneryAccuracyResolver owns every error source.

const EPSILON := 0.0001
const MAX_LEAD_ITERATIONS := 5
const LEAD_CONVERGENCE_TOLERANCE_M := 1.0
const MAXIMUM_SHELL_FLIGHT_TIME_SEC := 60.0


## Solves the low-arc ballistic launch toward a fixed world point using the
## same math as CannonMount._calculate_ballistic_pitch_deg, so prediction and
## the actual launch contract share one authoritative model.
static func solve_ballistic_to_point(
		launch_position: Vector3,
		target_point: Vector3,
		projectile_speed_mps: float,
		gravity_mps2: float,
		preferred_arc: BallisticSolution.ArcType = BallisticSolution.ArcType.LOW
) -> BallisticSolution:
	if not launch_position.is_finite() or not target_point.is_finite():
		return BallisticSolution.failed(&"invalid_input")
	if is_nan(projectile_speed_mps) or is_inf(projectile_speed_mps) \
			or projectile_speed_mps <= EPSILON:
		return BallisticSolution.failed(&"invalid_projectile_speed")
	if is_nan(gravity_mps2) or is_inf(gravity_mps2) or gravity_mps2 < 0.0:
		return BallisticSolution.failed(&"invalid_gravity")
	if preferred_arc != BallisticSolution.ArcType.LOW:
		return BallisticSolution.failed(&"unsupported_ballistic_arc")
	var horizontal_offset := Vector2(
		target_point.x - launch_position.x,
		target_point.z - launch_position.z
	)
	var horizontal_distance := horizontal_offset.length()
	if horizontal_distance <= EPSILON:
		return BallisticSolution.failed(&"degenerate_horizontal_distance")
	var vertical_offset := target_point.y - launch_position.y
	var angle_value: Variant = BallisticMath.solve_low_arc_angle(
		horizontal_distance,
		vertical_offset,
		projectile_speed_mps,
		gravity_mps2
	)
	if angle_value == null:
		return BallisticSolution.failed(&"no_ballistic_solution")
	var elevation_rad := float(angle_value)
	var flight_time_value: Variant = BallisticMath.calculate_flight_time(
		vertical_offset,
		projectile_speed_mps,
		elevation_rad,
		gravity_mps2
	)
	if flight_time_value == null:
		return BallisticSolution.failed(&"no_flight_time")
	var flight_time := float(flight_time_value)
	if flight_time <= 0.0:
		# A zero-gravity flat solution can legitimately return the linear time.
		if gravity_mps2 > EPSILON or flight_time < 0.0:
			return BallisticSolution.failed(&"invalid_flight_time")
	var horizontal_direction := Vector3(
		horizontal_offset.x,
		0.0,
		horizontal_offset.y
	) / horizontal_distance
	var result := BallisticSolution.new()
	result.success = true
	result.arc_type = preferred_arc
	result.elevation_rad = elevation_rad
	result.estimated_flight_time_sec = flight_time
	result.horizontal_distance_m = horizontal_distance
	result.launch_direction = (
		horizontal_direction * cos(elevation_rad)
		+ Vector3.UP * sin(elevation_rad)
	).normalized()
	result.launch_velocity = result.launch_direction * projectile_speed_mps
	result.predicted_impact_position = target_point
	return result


## Iteratively converges the intercept point of a moving target: the flight
## time changes the predicted position, which changes the flight time.
static func solve(
		launch_position: Vector3,
		target_position: Vector3,
		target_velocity: Vector3,
		projectile_speed_mps: float,
		gravity_mps2: float,
		preferred_arc: BallisticSolution.ArcType = BallisticSolution.ArcType.LOW
) -> NavalGunLeadResult:
	if not launch_position.is_finite() \
			or not target_position.is_finite() \
			or not target_velocity.is_finite():
		return NavalGunLeadResult.failed(&"invalid_input")
	if is_nan(projectile_speed_mps) or is_inf(projectile_speed_mps) \
			or projectile_speed_mps <= EPSILON:
		return NavalGunLeadResult.failed(&"invalid_projectile_speed")
	if is_nan(gravity_mps2) or is_inf(gravity_mps2) or gravity_mps2 < 0.0:
		return NavalGunLeadResult.failed(&"invalid_gravity")
	var flat_velocity := target_velocity
	flat_velocity.y = 0.0
	var predicted_position := target_position
	var last_solution: BallisticSolution = null
	for _iteration in MAX_LEAD_ITERATIONS:
		var ballistic := solve_ballistic_to_point(
			launch_position,
			predicted_position,
			projectile_speed_mps,
			gravity_mps2,
			preferred_arc
		)
		if not ballistic.success:
			return NavalGunLeadResult.failed(ballistic.failure_reason)
		var flight_time := ballistic.estimated_flight_time_sec
		if flight_time < 0.0 \
				or flight_time > MAXIMUM_SHELL_FLIGHT_TIME_SEC:
			return NavalGunLeadResult.failed(
				&"invalid_projectile_flight_time"
			)
		last_solution = ballistic
		var next_prediction := target_position + flat_velocity * flight_time
		next_prediction.y = target_position.y
		if next_prediction.distance_to(predicted_position) \
				<= LEAD_CONVERGENCE_TOLERANCE_M:
			predicted_position = next_prediction
			break
		predicted_position = next_prediction
	if last_solution == null:
		return NavalGunLeadResult.failed(&"no_ballistic_solution")
	var result := NavalGunLeadResult.new()
	result.success = true
	result.launch_position = launch_position
	result.target_current_position = target_position
	result.target_velocity = flat_velocity
	result.predicted_impact_position = predicted_position
	result.projectile_flight_time_sec = last_solution.estimated_flight_time_sec
	result.horizontal_distance_m = last_solution.horizontal_distance_m
	result.projectile_speed_mps = projectile_speed_mps
	result.elevation_rad = last_solution.elevation_rad
	result.arc_type = last_solution.arc_type
	return result
