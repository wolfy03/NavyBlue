extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, 120.0, 45.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		var controller: AircraftDiveBombController = fixture["controller"]
		if controller.attack_state.alignment_timeout_sec < 3.99:
			_failures.append("timeout does not reflect the 2.67-second turn")
		for _frame in 30:
			DiveBombAlignmentTestSupport.step(fixture)
		if controller.attack_state.state \
				!= DiveBombAircraftAttackState.State.ALIGNING:
			_failures.append("large QUICK turn failed or dived at 0.5 seconds")
		var result := DiveBombAlignmentTestSupport.run_until_dive(fixture)
		var total_elapsed := 0.5 + float(result["elapsed_sec"])
		if not result["completed"]:
			_failures.append("120-degree QUICK turn completes")
		if total_elapsed < 2.65:
			_failures.append("120-degree turn completed too quickly")
		if float(result["maximum_turn_rate_deg_sec"]) > 45.01:
			_failures.append("large turn exceeded the yaw limit")
		print(
			"MEASURE quick_120 elapsed=%.3f avg_rate=%.3f max_rate=%.3f"
			% [
				total_elapsed,
				float(result["average_turn_rate_deg_sec"]),
				float(result["maximum_turn_rate_deg_sec"]),
			]
		)
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_QUICK_ATTACK_LARGE_TURN_TEST", _failures
	)
