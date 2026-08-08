extends SceneTree


func _initialize() -> void:
	var delta := 0.02
	var limit := 30.0
	var current := Vector3.FORWARD
	var next := AircraftSteeringMath.resolve_horizontal_steered_direction(
		current, Vector3.LEFT, limit, delta
	)
	var step := rad_to_deg(current.signed_angle_to(next, Vector3.UP))
	var passed := absf(step - limit * delta) < 0.001
	if not passed:
		push_error("clamped step was %.4f degrees" % step)
	print("AIRCRAFT_STEERING_MATH_TURN_RATE_CLAMP_TEST %s" % (
		"PASS" if passed else "FAIL"
	))
	quit(0 if passed else 1)
