extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, 150.0, 10.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		var controller: AircraftDiveBombController = fixture["controller"]
		var aircraft: AircraftUnit = fixture["aircraft"]
		var ammunition_before := aircraft.weapon_controller.remaining_ammunition
		controller.attack_state.alignment_timeout_sec = 0.2
		for _frame in 20:
			DiveBombAlignmentTestSupport.step(fixture)
		if controller.attack_state.state not in [
			DiveBombAircraftAttackState.State.PULLING_OUT,
			DiveBombAircraftAttackState.State.REGROUPING,
		]:
			_failures.append("timed-out aircraft begins pull-out/regroup")
		if controller.attack_state.release_block_reason \
				!= DiveBombReleaseBlockReason.Type.ALIGNMENT_TIMEOUT:
			_failures.append("timeout has a dedicated block reason")
		if aircraft.weapon_controller.remaining_ammunition != ammunition_before:
			_failures.append("alignment timeout preserves ammunition")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_TIMEOUT_TEST", _failures
	)
