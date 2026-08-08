extends SceneTree


func _initialize() -> void:
	var current := Vector3.FORWARD
	var next := AircraftSteeringMath.resolve_horizontal_steered_direction(
		current, Vector3.LEFT, 45.0, 1.0 / 60.0
	)
	var step := rad_to_deg(current.signed_angle_to(next, Vector3.UP))
	var passed := step > 0.0 and step <= 0.751
	if not passed:
		push_error("left steering step was %.4f degrees" % step)
	print("AIRCRAFT_STEERING_MATH_TURN_LEFT_TEST %s" % (
		"PASS" if passed else "FAIL"
	))
	quit(0 if passed else 1)
