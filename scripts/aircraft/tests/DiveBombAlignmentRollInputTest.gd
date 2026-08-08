extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, 45.0, 45.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		var aircraft: AircraftUnit = fixture["aircraft"]
		for _frame in 30:
			DiveBombAlignmentTestSupport.step(fixture)
		if aircraft.visual_controller.get_current_bank_angle_rad() <= 0.01:
			_failures.append("left alignment turn does not feed positive bank")
		if absf(aircraft.rotation.z) > 0.0001:
			_failures.append("physics root rolled during visual banking")
		var result := DiveBombAlignmentTestSupport.run_until_dive(fixture)
		if not result["completed"]:
			_failures.append("alignment completes before bank-return check")
		for _frame in 180:
			aircraft.update_visual_bank(DiveBombAlignmentTestSupport.DELTA)
		if absf(aircraft.visual_controller.get_current_bank_angle_rad()) > 0.01:
			_failures.append("stable dive track does not return bank to zero")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_ROLL_INPUT_TEST", _failures
	)
