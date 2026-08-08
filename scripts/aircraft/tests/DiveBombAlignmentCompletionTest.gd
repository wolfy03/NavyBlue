extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, 30.0, 45.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		var result := DiveBombAlignmentTestSupport.run_until_dive(fixture)
		var state = fixture["controller"].attack_state
		if not result["completed"]:
			_failures.append("aligned aircraft enters DIVING")
		if not state.final_solution_ready:
			_failures.append("final solution is ready before DIVING")
		if state.final_solution_revision <= fixture["initial_solution_revision"]:
			_failures.append("final solution receives a newer revision")
		if absf(state.current_turn_rate_degrees_sec) > 8.01:
			_failures.append("DIVING began before turn rate settled")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_COMPLETION_TEST", _failures
	)
