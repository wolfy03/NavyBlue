extends SceneTree

var _failures: Array[String] = []
var _fixtures: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	for angle in [30.0, 90.0, 150.0]:
		var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
			self, angle, 45.0
		)
		_fixtures.append(fixture)
		if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
			_failures.append("%.0f-degree fixture initializes" % angle)
			continue
		var result := DiveBombAlignmentTestSupport.run_until_dive(
			fixture, 600
		)
		if not result["completed"]:
			_failures.append("%.0f-degree turn reaches DIVING" % angle)
		if float(result["maximum_turn_rate_deg_sec"]) > 45.01:
			_failures.append("%.0f-degree turn exceeds yaw limit" % angle)
		print(
			"MEASURE quick_%.0f elapsed=%.3f avg_rate=%.3f max_rate=%.3f"
			% [
				angle,
				float(result["elapsed_sec"]),
				float(result["average_turn_rate_deg_sec"]),
				float(result["maximum_turn_rate_deg_sec"]),
			]
		)
		fixture["coordinator"].cancel(&"profile_case_finished")
		fixture["battle"].queue_free()
		await process_frame
		await process_frame
	for failure in _failures:
		push_error("DIVE_BOMB_QUICK_ATTACK_TURN_PROFILE_TEST: %s" % failure)
	print("DIVE_BOMB_QUICK_ATTACK_TURN_PROFILE_TEST %s" % (
		"PASS" if _failures.is_empty() else "FAIL"
	))
	quit(0 if _failures.is_empty() else 1)
