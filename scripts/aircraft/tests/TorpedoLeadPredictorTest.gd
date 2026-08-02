extends SceneTree

# Verifies TorpedoLeadPredictor.predict_impact leads a moving target correctly:
# stationary targets are unchanged, moving targets are led along their velocity,
# a faster target is led further, and a slower aircraft (more travel time) leads
# further. Also verifies the torpedo's underwater run time extends the lead and
# matches the accelerate-then-cruise kinematics. Pure math, no scene
# instantiation.

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var center := Vector3.ZERO
	var target := Vector3(0.0, 0.0, -1000.0)

	var stationary := TorpedoLeadPredictor.predict_impact(
		center, 100.0, target, Vector3.ZERO, 25.0, 9.8
	)
	_check(
		stationary.is_equal_approx(target),
		"stationary target keeps the current position"
	)

	var moving := TorpedoLeadPredictor.predict_impact(
		center, 100.0, target, Vector3(50.0, 0.0, 0.0), 25.0, 9.8
	)
	_check(moving.x > target.x + 1.0, "moving target is led ahead of it")
	_check(
		absf(moving.z - target.z) < 1.0,
		"lead stays on the velocity axis"
	)

	var faster_target := TorpedoLeadPredictor.predict_impact(
		center, 100.0, target, Vector3(100.0, 0.0, 0.0), 25.0, 9.8
	)
	_check(
		faster_target.x > moving.x,
		"a faster target is led further ahead"
	)

	var slower_aircraft := TorpedoLeadPredictor.predict_impact(
		center, 50.0, target, Vector3(50.0, 0.0, 0.0), 25.0, 9.8
	)
	_check(
		slower_aircraft.x > moving.x,
		"a slower aircraft (more travel time) leads further"
	)

	# The torpedo's underwater run adds to the timeline, so the same target is
	# led further ahead when a run time is supplied.
	var with_run := TorpedoLeadPredictor.predict_impact(
		center, 100.0, target, Vector3(50.0, 0.0, 0.0), 25.0, 9.8, 6.0
	)
	_check(
		with_run.x > moving.x,
		"a torpedo run time leads further than water-entry alone"
	)

	# torpedo_run_time: a longer run takes longer, and covers the accelerating
	# phase (0 -> 112.5m at 15..30 m/s, 3 m/s^2) before cruising at top speed.
	var short_run := TorpedoLeadPredictor.torpedo_run_time(50.0, 15.0, 30.0, 3.0)
	var long_run := TorpedoLeadPredictor.torpedo_run_time(300.0, 15.0, 30.0, 3.0)
	_check(short_run > 0.0, "a positive run distance yields a positive run time")
	_check(long_run > short_run, "a longer torpedo run takes more time")
	_check(
		TorpedoLeadPredictor.torpedo_run_time(0.0, 15.0, 30.0, 3.0) == 0.0,
		"a zero run distance yields no run time"
	)
	# 150m: 112.5m accelerating (reaches 30 m/s at t=5s) + 37.5m at 30 m/s.
	var known := TorpedoLeadPredictor.torpedo_run_time(150.0, 15.0, 30.0, 3.0)
	_check(
		absf(known - 6.25) < 0.01,
		"run time matches the analytic accelerate-then-cruise value"
	)

	print(
		"TORPEDO_LEAD_PREDICTOR_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO LEAD: %s" % label)
