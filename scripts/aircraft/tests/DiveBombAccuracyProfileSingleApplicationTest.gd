extends SceneTree
## Accuracy is applied exactly once: the planner rolls one deterministic
## offset per pass, the final aim is exact + offset, and repeated re-solves
## of the same pass never re-apply or accumulate dispersion.

const AIRCRAFT_SCENE := preload("res://scenes/aircraft/aircraft_unit.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var reference := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	root.add_child(reference)
	reference.global_position = Vector3(0.0, 350.0, -1500.0)
	var dive_data := _make_dive_data(0.4)
	var weapon := AircraftWeaponData.new()
	weapon.downward_release_speed_mps = 20.0
	var target := _position_target(Vector3.ZERO)
	var context := DiveBombAttackContext.new()
	context.squadron_combat_id = 777
	context.reset_for_new_pass()
	var solution := DiveBombAttackPlanner.build_aircraft_commit_solution(
		null, reference, target, dive_data, weapon, context
	)
	_check(solution != null and solution.valid, "commit solution solves")
	if solution == null or not solution.valid:
		_finish(reference)
		return
	_check(
		context.pass_dispersion_offset != Vector3.ZERO,
		"reduced accuracy rolls a non-zero offset"
	)
	_check(
		solution.final_aim_impact_position.is_equal_approx(
			solution.exact_intended_impact_position
				+ context.pass_dispersion_offset
		),
		"final aim = exact intended + the single pass offset"
	)
	_check(
		solution.dispersion_offset == context.pass_dispersion_offset,
		"the solution records exactly the pass offset"
	)
	var offset_after_first := context.pass_dispersion_offset
	# Re-solve the same pass (repath): the offset must neither change nor
	# stack a second application.
	var repath := DiveBombAttackPlanner.build_aircraft_commit_solution(
		null, reference, target, dive_data, weapon, context
	)
	_check(
		context.pass_dispersion_offset == offset_after_first,
		"a repath re-solve keeps the same offset"
	)
	_check(
		repath.final_aim_impact_position.is_equal_approx(
			repath.exact_intended_impact_position + offset_after_first
		),
		"a repath re-solve applies the offset exactly once"
	)
	_finish(reference)


func _make_dive_data(accuracy: float) -> DiveBomberCombatData:
	var data := DiveBomberCombatData.new()
	var profile := DiveBombAccuracyProfile.new()
	profile.base_accuracy = accuracy
	profile.perfect_accuracy_dispersion_m = 0.0
	profile.minimum_accuracy_dispersion_m = 150.0
	data.accuracy_profile = profile
	return data


func _position_target(position: Vector3) -> DiveBombResolvedTarget:
	var request := DiveBombTargetRequest.new()
	request.designated_world_position = position
	var empty: Array[ShipUnit] = []
	return DiveBombTargetResolver.resolve(request, empty)


func _finish(reference: AircraftUnit) -> void:
	reference.queue_free()
	for failure in _failures:
		push_error("SINGLE APPLICATION: %s" % failure)
	print(
		"DIVE_BOMB_ACCURACY_PROFILE_SINGLE_APPLICATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
