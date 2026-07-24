extends RefCounted
class_name BallisticMath

const EPSILON := 0.00001


static func get_effective_gravity_mps2(
		shell_data: ShellProjectileData = null,
		fallback_scale: float = 1.0
) -> float:
	var world_gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var scale := shell_data.gravity_scale \
		if shell_data != null else fallback_scale
	return world_gravity * maxf(scale, 0.0)


static func solve_low_arc_angle(
		horizontal_distance: float,
		vertical_offset: float,
		muzzle_speed: float,
		gravity_mps2: float
) -> Variant:
	if horizontal_distance <= EPSILON or muzzle_speed <= EPSILON:
		return null
	if gravity_mps2 <= EPSILON:
		return atan2(vertical_offset, horizontal_distance)
	var speed_squared := muzzle_speed * muzzle_speed
	var discriminant := speed_squared * speed_squared - gravity_mps2 * (
		gravity_mps2 * horizontal_distance * horizontal_distance
		+ 2.0 * vertical_offset * speed_squared
	)
	if discriminant < 0.0:
		return null
	var tangent := (
		speed_squared - sqrt(maxf(discriminant, 0.0))
	) / (gravity_mps2 * horizontal_distance)
	return atan(tangent)


static func calculate_position(
		start_position: Vector3,
		initial_velocity: Vector3,
		gravity_mps2: float,
		time_seconds: float
) -> Vector3:
	var time := maxf(time_seconds, 0.0)
	return start_position \
		+ initial_velocity * time \
		+ Vector3.DOWN * gravity_mps2 * 0.5 * time * time


static func calculate_flight_time(
		vertical_offset: float,
		muzzle_speed: float,
		launch_angle_radians: float,
		gravity_mps2: float
) -> Variant:
	var vertical_speed := muzzle_speed * sin(launch_angle_radians)
	if gravity_mps2 <= EPSILON:
		if absf(vertical_speed) <= EPSILON:
			return 0.0 if absf(vertical_offset) <= EPSILON else null
		var linear_time := vertical_offset / vertical_speed
		return linear_time if linear_time >= 0.0 else null
	var discriminant := vertical_speed * vertical_speed \
		- 2.0 * gravity_mps2 * vertical_offset
	if discriminant < 0.0:
		return null
	var root := sqrt(maxf(discriminant, 0.0))
	var first_time := (vertical_speed - root) / gravity_mps2
	var second_time := (vertical_speed + root) / gravity_mps2
	var flight_time := maxf(first_time, second_time)
	return flight_time if flight_time >= 0.0 else null


static func calculate_time_to_height(
		start_height: float,
		target_height: float,
		initial_vertical_velocity: float,
		gravity_mps2: float
) -> Variant:
	if start_height <= target_height:
		return 0.0
	if gravity_mps2 <= EPSILON:
		return null
	var height_offset := target_height - start_height
	var discriminant := initial_vertical_velocity * initial_vertical_velocity \
		- 2.0 * gravity_mps2 * height_offset
	if discriminant < 0.0:
		return null
	var root := sqrt(maxf(discriminant, 0.0))
	var first_time := (
		initial_vertical_velocity - root
	) / gravity_mps2
	var second_time := (
		initial_vertical_velocity + root
	) / gravity_mps2
	var valid_time := maxf(first_time, second_time)
	return valid_time if valid_time >= 0.0 else null


static func calculate_maximum_range(
		muzzle_speed: float,
		gravity_mps2: float,
		maximum_pitch_degrees: float,
		start_height: float = 0.0,
		target_height: float = 0.0
) -> float:
	if muzzle_speed <= EPSILON or gravity_mps2 <= EPSILON:
		return 0.0
	var optimal_pitch_degrees := clampf(
		45.0,
		0.0,
		maxf(maximum_pitch_degrees, 0.0)
	)
	var launch_angle := deg_to_rad(optimal_pitch_degrees)
	var flight_time_value: Variant = calculate_flight_time(
		target_height - start_height,
		muzzle_speed,
		launch_angle,
		gravity_mps2
	)
	if flight_time_value == null:
		return 0.0
	return muzzle_speed * cos(launch_angle) * float(flight_time_value)
