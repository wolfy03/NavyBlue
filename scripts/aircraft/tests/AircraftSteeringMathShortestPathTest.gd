extends SceneTree


func _initialize() -> void:
	var current := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(170.0))
	var desired := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-170.0))
	var error := rad_to_deg(
		AircraftSteeringMath.signed_heading_error_rad(current, desired)
	)
	var reverse_error := rad_to_deg(
		AircraftSteeringMath.signed_heading_error_rad(desired, current)
	)
	var passed := absf(error - 20.0) < 0.01 \
		and absf(reverse_error + 20.0) < 0.01
	if not passed:
		push_error("shortest errors were %.3f / %.3f" % [error, reverse_error])
	print("AIRCRAFT_STEERING_MATH_SHORTEST_PATH_TEST %s" % (
		"PASS" if passed else "FAIL"
	))
	quit(0 if passed else 1)
