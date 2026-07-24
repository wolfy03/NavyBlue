extends RefCounted
class_name ShellRangeTestRunner


static func evaluate_ranges(
		muzzle_speed: float,
		gravity_mps2: float,
		configured_range_m: float,
		start_height_m: float = 10.0,
		target_height_m: float = 0.0
) -> Array[Dictionary]:
	var distances: Array[float] = [
		1000.0,
		3000.0,
		5000.0,
		configured_range_m * 0.5,
		configured_range_m * 0.75,
		configured_range_m * 0.9,
		configured_range_m,
		configured_range_m + 100.0,
	]
	var unique_distances: Array[float] = []
	for distance in distances:
		if distance <= 0.0:
			continue
		var duplicate := false
		for existing in unique_distances:
			if is_equal_approx(existing, distance):
				duplicate = true
				break
		if not duplicate:
			unique_distances.append(distance)
	unique_distances.sort()

	var results: Array[Dictionary] = []
	for distance in unique_distances:
		results.append(_evaluate_range(
			distance,
			muzzle_speed,
			gravity_mps2,
			configured_range_m,
			start_height_m,
			target_height_m
		))
	return results


static func _evaluate_range(
		distance_m: float,
		muzzle_speed: float,
		gravity_mps2: float,
		configured_range_m: float,
		start_height_m: float,
		target_height_m: float
) -> Dictionary:
	if distance_m > configured_range_m:
		return {
			"distance_m": distance_m,
			"status": &"OUT_OF_RANGE",
			"has_solution": false,
			"angle_degrees": 0.0,
			"actual_distance_m": 0.0,
			"error_m": 0.0,
			"flight_time_seconds": 0.0,
		}
	var angle_value: Variant = BallisticMath.solve_low_arc_angle(
		distance_m,
		target_height_m - start_height_m,
		muzzle_speed,
		gravity_mps2
	)
	if angle_value == null:
		return {
			"distance_m": distance_m,
			"status": &"NO_BALLISTIC_SOLUTION",
			"has_solution": false,
			"angle_degrees": 0.0,
			"actual_distance_m": 0.0,
			"error_m": 0.0,
			"flight_time_seconds": 0.0,
		}
	var angle := float(angle_value)
	var flight_time_value: Variant = BallisticMath.calculate_flight_time(
		target_height_m - start_height_m,
		muzzle_speed,
		angle,
		gravity_mps2
	)
	if flight_time_value == null:
		return {
			"distance_m": distance_m,
			"status": &"NO_BALLISTIC_SOLUTION",
			"has_solution": false,
			"angle_degrees": rad_to_deg(angle),
			"actual_distance_m": 0.0,
			"error_m": 0.0,
			"flight_time_seconds": 0.0,
		}
	var flight_time := float(flight_time_value)
	var initial_velocity := Vector3(
		muzzle_speed * cos(angle),
		muzzle_speed * sin(angle),
		0.0
	)
	var impact_position := BallisticMath.calculate_position(
		Vector3(0.0, start_height_m, 0.0),
		initial_velocity,
		gravity_mps2,
		flight_time
	)
	var actual_distance := absf(impact_position.x)
	return {
		"distance_m": distance_m,
		"status": &"OK",
		"has_solution": true,
		"angle_degrees": rad_to_deg(angle),
		"actual_distance_m": actual_distance,
		"error_m": absf(actual_distance - distance_m),
		"flight_time_seconds": flight_time,
	}
