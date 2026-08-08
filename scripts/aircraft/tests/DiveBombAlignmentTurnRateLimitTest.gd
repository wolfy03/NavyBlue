extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, -90.0, 45.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		var maximum_rate := 0.0
		for _frame in 90:
			DiveBombAlignmentTestSupport.step(fixture)
			maximum_rate = maxf(maximum_rate, absf(
				fixture["controller"].attack_state \
					.current_turn_rate_degrees_sec
			))
		if maximum_rate > 45.01:
			_failures.append("observed turn rate %.3f exceeds 45" % maximum_rate)
		if maximum_rate < 44.0:
			_failures.append("turn never approached its configured rate")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_TURN_RATE_LIMIT_TEST", _failures
	)
