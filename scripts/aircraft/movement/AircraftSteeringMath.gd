extends RefCounted
class_name AircraftSteeringMath
## Pure, reusable horizontal steering math. It never owns movement or writes
## transforms; callers decide how the resolved track is applied.

const EPSILON := 0.0001


static func horizontal_heading(
		direction: Vector3,
		fallback_forward: Vector3 = Vector3.FORWARD
) -> Vector3:
	var heading := direction
	heading.y = 0.0
	if heading.length_squared() <= EPSILON:
		heading = fallback_forward
		heading.y = 0.0
	if heading.length_squared() <= EPSILON:
		return Vector3.FORWARD
	return heading.normalized()


static func signed_heading_error_rad(
		current_heading: Vector3,
		desired_heading: Vector3
) -> float:
	var current := horizontal_heading(current_heading)
	var desired := horizontal_heading(desired_heading, current)
	return current.signed_angle_to(desired, Vector3.UP)


static func resolve_turn_step_rad(
		current_heading: Vector3,
		desired_heading: Vector3,
		max_turn_rate_rad_sec: float,
		delta: float
) -> float:
	var maximum_step := maxf(max_turn_rate_rad_sec, 0.0) * maxf(delta, 0.0)
	return clampf(
		signed_heading_error_rad(current_heading, desired_heading),
		-maximum_step,
		maximum_step
	)


static func steer_toward(
		current_heading: Vector3,
		desired_heading: Vector3,
		max_turn_rate_rad_sec: float,
		delta: float
) -> Vector3:
	var current := horizontal_heading(current_heading)
	var turn_step := resolve_turn_step_rad(
		current,
		desired_heading,
		max_turn_rate_rad_sec,
		delta
	)
	return horizontal_heading(current.rotated(Vector3.UP, turn_step), current)


static func resolve_horizontal_steered_direction(
		current_direction: Vector3,
		desired_direction: Vector3,
		max_turn_rate_degrees_sec: float,
		delta: float
) -> Vector3:
	return steer_toward(
		current_direction,
		desired_direction,
		deg_to_rad(maxf(max_turn_rate_degrees_sec, 0.0)),
		delta
	)


static func estimated_turn_time_sec(
		current_heading: Vector3,
		desired_heading: Vector3,
		max_turn_rate_degrees_sec: float
) -> float:
	var turn_rate_rad_sec := deg_to_rad(maxf(max_turn_rate_degrees_sec, 0.0))
	if turn_rate_rad_sec <= EPSILON:
		return INF
	return absf(signed_heading_error_rad(current_heading, desired_heading)) \
		/ turn_rate_rad_sec
