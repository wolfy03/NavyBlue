extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, 20.0, 45.0, Vector3(18.0, 0.0, 0.0)
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		var result := DiveBombAlignmentTestSupport.run_until_dive(fixture)
		var state = fixture["controller"].attack_state
		if not result["completed"]:
			_failures.append("moving-target alignment reaches final lock")
		if not state.final_solution_ready:
			_failures.append("final solver ran before DIVING")
		if state.final_solution_revision <= fixture["initial_solution_revision"]:
			_failures.append("final solver produced exactly one newer solution")
		if state.solution.revision != state.final_solution_revision:
			_failures.append("DIVING owns the final cached revision")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_FINAL_SOLUTION_RELOCK_TEST", _failures
	)
