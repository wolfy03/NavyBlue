extends SceneTree


func _integrate(delta: float) -> Vector3:
	var heading := Vector3.FORWARD
	var steps := roundi(1.0 / delta)
	for _step in steps:
		heading = AircraftSteeringMath.resolve_horizontal_steered_direction(
			heading, Vector3.LEFT, 45.0, delta
		)
	return heading


func _initialize() -> void:
	var at_30 := _integrate(1.0 / 30.0)
	var at_60 := _integrate(1.0 / 60.0)
	var at_120 := _integrate(1.0 / 120.0)
	var expected := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(45.0))
	var passed := at_30.angle_to(expected) < 0.0001 \
		and at_60.angle_to(expected) < 0.0001 \
		and at_120.angle_to(expected) < 0.0001
	if not passed:
		push_error("one-second headings differ across physics deltas")
	print("AIRCRAFT_STEERING_MATH_DELTA_INDEPENDENCE_TEST %s" % (
		"PASS" if passed else "FAIL"
	))
	quit(0 if passed else 1)
