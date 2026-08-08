extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, 90.0
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
		await DiveBombAlignmentTestSupport.finish(
			self, fixture, "DIVE_BOMB_ALIGNMENT_NO_HEADING_SNAP_TEST", _failures
		)
		return
	var aircraft: AircraftUnit = fixture["aircraft"]
	var before := DiveBombAlignmentTestSupport.horizontal_heading(aircraft)
	DiveBombAlignmentTestSupport.step(fixture)
	var after := DiveBombAlignmentTestSupport.horizontal_heading(aircraft)
	var change := rad_to_deg(before.angle_to(after))
	if change > 0.751:
		_failures.append("first-frame yaw %.3f exceeds 0.75 degrees" % change)
	if after.angle_to(fixture["desired_heading"]) < deg_to_rad(80.0):
		_failures.append("first frame snapped to the target heading")
	if fixture["controller"].attack_state.state \
			!= DiveBombAircraftAttackState.State.ALIGNING:
		_failures.append("90-degree attack remains ALIGNING after one frame")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_NO_HEADING_SNAP_TEST", _failures
	)
