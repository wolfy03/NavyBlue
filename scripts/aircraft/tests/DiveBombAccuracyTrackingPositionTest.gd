extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var resolved := _position_target(Vector3(420.0, 0.0, -180.0))
	var inaccurate_data := _make_dive_data(0.0)
	var inaccurate_context := DiveBombAttackContext.new()
	inaccurate_context.squadron_combat_id = 921
	inaccurate_context.attack_pass_index = 3
	DiveBombAttackPlanner.ensure_pass_dispersion(
		inaccurate_context,
		resolved,
		inaccurate_data
	)
	var inaccurate_tracking := DiveBombAttackPlanner \
		.resolve_tracking_aim_position(resolved, inaccurate_context)
	_check(
		inaccurate_context.pass_dispersion_offset != Vector3.ZERO,
		"low accuracy produces a deterministic tracking offset"
	)
	_check(
		inaccurate_tracking.is_equal_approx(
			resolved.get_aim_position()
				+ inaccurate_context.pass_dispersion_offset
		),
		"tracking follows the accuracy-biased position"
	)
	var perfect_data := _make_dive_data(1.0)
	var perfect_context := DiveBombAttackContext.new()
	perfect_context.squadron_combat_id = 921
	perfect_context.attack_pass_index = 3
	DiveBombAttackPlanner.ensure_pass_dispersion(
		perfect_context,
		resolved,
		perfect_data
	)
	_check(
		DiveBombAttackPlanner.resolve_tracking_aim_position(
			resolved,
			perfect_context
		).is_equal_approx(resolved.get_aim_position()),
		"perfect accuracy tracks the exact target position"
	)
	for failure in _failures:
		push_error("DIVE TRACKING ACCURACY: %s" % failure)
	print("DIVE_BOMB_ACCURACY_TRACKING_POSITION_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


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


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
