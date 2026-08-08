extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, -45.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		for _frame in 30:
			DiveBombAlignmentTestSupport.step(fixture)
		var aircraft: AircraftUnit = fixture["aircraft"]
		if aircraft.visual_controller.get_current_bank_angle_rad() >= -0.01:
			_failures.append("right velocity turn produces right visual bank")
		if absf(aircraft.rotation.z) > 0.0001:
			_failures.append("physics root remains unrolled")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_VISUAL_BANK_RIGHT_TEST", _failures
	)
