extends SceneTree
## Accuracy 1.0 with a perfect-dispersion of zero aims exactly: no offset,
## final aim equals the exact intended impact.

const AIRCRAFT_SCENE := preload("res://scenes/aircraft/aircraft_unit.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var reference := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	root.add_child(reference)
	reference.global_position = Vector3(0.0, 350.0, -1500.0)
	var data := DiveBomberCombatData.new()
	var profile := DiveBombAccuracyProfile.new()
	profile.base_accuracy = 1.0
	profile.perfect_accuracy_dispersion_m = 0.0
	profile.minimum_accuracy_dispersion_m = 150.0
	data.accuracy_profile = profile
	_check(
		profile.resolve_dispersion_radius_m() == 0.0,
		"accuracy 1.0 resolves a zero dispersion radius"
	)
	var weapon := AircraftWeaponData.new()
	weapon.downward_release_speed_mps = 20.0
	var request := DiveBombTargetRequest.new()
	request.designated_world_position = Vector3.ZERO
	var empty: Array[ShipUnit] = []
	var target := DiveBombTargetResolver.resolve(request, empty)
	var context := DiveBombAttackContext.new()
	context.squadron_combat_id = 777
	context.reset_for_new_pass()
	var solution := DiveBombAttackPlanner.build_commit_solution(
		null, reference, target, data, weapon, context
	)
	_check(solution != null and solution.valid, "commit solution solves")
	if solution != null and solution.valid:
		_check(
			context.pass_dispersion_offset == Vector3.ZERO,
			"accuracy 1.0 rolls a zero offset"
		)
		_check(
			solution.final_aim_impact_position.is_equal_approx(
				solution.exact_intended_impact_position
			),
			"the final aim equals the exact intended impact"
		)
		_check(
			solution.dispersion_radius_m == 0.0,
			"the solution reports zero dispersion"
		)
	reference.queue_free()
	for failure in _failures:
		push_error("PERFECT ACCURACY: %s" % failure)
	print(
		"DIVE_BOMB_ACCURACY_PROFILE_PERFECT_ACCURACY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
