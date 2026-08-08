extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, -60.0, 45.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		var controller: AircraftDiveBombController = fixture["controller"]
		var aircraft: AircraftUnit = fixture["aircraft"]
		var entry_heading := Vector3.ZERO
		for _frame in 600:
			DiveBombAlignmentTestSupport.step(fixture)
			if controller.attack_state.state \
					== DiveBombAircraftAttackState.State.DIVING:
				entry_heading = DiveBombAlignmentTestSupport \
					.horizontal_heading(aircraft)
				break
		if entry_heading == Vector3.ZERO:
			_failures.append("alignment reaches DIVING")
		else:
			var locked := AircraftSteeringMath.horizontal_heading(
				controller.attack_state.locked_dive_direction
			)
			var lock_error := rad_to_deg(entry_heading.angle_to(locked))
			DiveBombAlignmentTestSupport.step(fixture)
			var first_dive_heading := DiveBombAlignmentTestSupport \
				.horizontal_heading(aircraft)
			var transition_change := rad_to_deg(
				entry_heading.angle_to(first_dive_heading)
			)
			if lock_error > 0.2:
				_failures.append("locked dive differs by %.3f degrees" % lock_error)
			if transition_change > 0.2:
				_failures.append("dive entry snapped by %.3f degrees" % transition_change)
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_TO_DIVE_CONTINUITY_TEST", _failures
	)
