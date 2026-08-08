extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await DiveBombAlignmentTestSupport.make_quick_fixture(
		self, 45.0, 45.0, Vector3(25.0, 0.0, 0.0)
	)
	if not DiveBombAlignmentTestSupport.is_complete_fixture(fixture):
		_failures.append("fixture initializes")
	else:
		DiveBombAlignmentTestSupport.step(fixture)
		var before: Vector3 = fixture["controller"].attack_state.desired_heading
		fixture["target"].global_position += Vector3(300.0, 0.0, 0.0)
		var intruder := (
			load("res://scenes/unit/ship.tscn") as PackedScene
		).instantiate() as ShipUnit
		intruder.team = &"enemy"
		intruder.combat_spawn_id = 900001
		fixture["battle"].add_child(intruder)
		intruder.global_position = fixture["target"].global_position \
			+ Vector3(10.0, 0.0, 0.0)
		intruder.set_physics_process(false)
		DiveBombAlignmentTestSupport.step(fixture, 0.0, false)
		var after: Vector3 = fixture["controller"].attack_state.desired_heading
		var snapshot: Dictionary = fixture["coordinator"].get_debug_snapshot()
		if before.angle_to(after) < deg_to_rad(1.0):
			_failures.append("desired heading does not track the locked ship")
		if int(snapshot["resolved_target_ship_id"]) \
				!= int(fixture["target_instance_id"]):
			_failures.append("ALIGNING changed target identity")
		if not is_instance_valid(intruder):
			_failures.append("tracking test intruder remains a separate target")
	await DiveBombAlignmentTestSupport.finish(
		self, fixture, "DIVE_BOMB_ALIGNMENT_MOVING_TARGET_TRACKING_TEST", _failures
	)
