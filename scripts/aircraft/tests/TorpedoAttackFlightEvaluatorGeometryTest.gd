extends SceneTree

# Unit-tests the pure attack-run geometry extracted into
# TorpedoAttackFlightEvaluator (heading alignment, run progress, release-line
# arrival, and the grace window). These are the judgments the controller now
# delegates instead of computing inline.

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var evaluator := TorpedoAttackFlightEvaluator.new()
	var direction := Vector3.FORWARD
	var entry := Vector3(0.0, 0.0, 700.0)
	var release := Vector3.ZERO

	_check(
		evaluator.is_heading_aligned(Vector3.FORWARD, direction, 5.0),
		"aligned heading passes"
	)
	_check(
		not evaluator.is_heading_aligned(Vector3.BACK, direction, 5.0),
		"reversed heading fails"
	)
	_check(
		not evaluator.is_heading_aligned(Vector3.UP, direction, 5.0),
		"vertical heading has no horizontal alignment"
	)

	_check(
		is_equal_approx(
			evaluator.required_progress(release, entry, direction),
			700.0
		),
		"required progress equals the run length"
	)
	_check(
		is_equal_approx(
			evaluator.run_progress(entry, entry, direction),
			0.0
		),
		"progress at the entry point is zero"
	)

	var command := TorpedoAttackCommand.new()
	command.entry_point = entry
	command.actual_release_point = release
	command.attack_direction = direction
	_check(
		evaluator.has_reached_release_line(release, command, 20.0),
		"formation at the release point has reached the release line"
	)
	_check(
		not evaluator.has_reached_release_line(entry, command, 20.0),
		"formation still at entry has not reached the release line"
	)

	_check(
		evaluator.is_release_window_missed(
			Vector3(0.0, 0.0, -130.0), release, direction, 120.0
		),
		"overshooting past the grace distance misses the window"
	)
	_check(
		not evaluator.is_release_window_missed(
			release, release, direction, 120.0
		),
		"sitting on the release point has not missed the window"
	)

	command = null
	evaluator = null
	print(
		"TORPEDO_ATTACK_FLIGHT_EVALUATOR_GEOMETRY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO EVALUATOR: %s" % label)
