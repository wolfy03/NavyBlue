extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, 30.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		var aircraft: AircraftUnit = fixture["aircraft"]
		for _frame in 20:
			DiveBombAlignmentTestSupport.step(fixture)
		if absf(aircraft.visual_controller.get_current_bank_angle_rad()) <= 0.01:
			_failures.append("alignment first establishes visible bank")
		var result := DiveBombAlignmentTestSupport.run_until_dive(fixture)
		if not result["completed"]:
			_failures.append("alignment reaches a stable dive heading")
		for _frame in 180:
			aircraft.update_visual_bank(DiveBombAlignmentTestSupport.DELTA)
		if absf(aircraft.visual_controller.get_current_bank_angle_rad()) > 0.01:
			_failures.append("stable heading returns visual bank to zero")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_VISUAL_BANK_RETURN_TEST", _failures
	)
