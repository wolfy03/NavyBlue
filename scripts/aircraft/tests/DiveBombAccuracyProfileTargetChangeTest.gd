extends SceneTree
## A mid-pass target change rolls a NEW deterministic offset; keeping the
## same target keeps the same offset through every repath.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var dive_data := _make_dive_data(0.0)
	var target_a := _position_target(Vector3(0.0, 0.0, 0.0))
	var target_b := _position_target(Vector3(300.0, 0.0, 120.0))
	var context := DiveBombAttackContext.new()
	context.squadron_combat_id = 777
	context.reset_for_new_pass()
	DiveBombAttackPlanner.ensure_pass_dispersion(context, target_a, dive_data)
	var offset_a := context.pass_dispersion_offset
	_check(offset_a != Vector3.ZERO, "accuracy 0.0 rolls a wide offset")
	# Repath on the same target: identical offset.
	DiveBombAttackPlanner.ensure_pass_dispersion(context, target_a, dive_data)
	_check(
		context.pass_dispersion_offset == offset_a,
		"the same target keeps the same offset across repaths"
	)
	# Target changes: a fresh deterministic roll.
	DiveBombAttackPlanner.ensure_pass_dispersion(context, target_b, dive_data)
	var offset_b := context.pass_dispersion_offset
	_check(
		offset_b != offset_a,
		"a target change rolls a new offset"
	)
	# And the new target's offset is itself stable.
	DiveBombAttackPlanner.ensure_pass_dispersion(context, target_b, dive_data)
	_check(
		context.pass_dispersion_offset == offset_b,
		"the new target's offset stays fixed afterwards"
	)
	for failure in _failures:
		push_error("TARGET CHANGE: %s" % failure)
	print(
		"DIVE_BOMB_ACCURACY_PROFILE_TARGET_CHANGE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
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
