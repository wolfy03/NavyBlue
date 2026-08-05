extends SceneTree
## The pass dispersion is deterministic: identical squadron/target/pass
## identities reproduce the identical offset across independent contexts,
## and re-solving inside one pass never changes it.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var dive_data := _make_dive_data(0.3)
	var target := _position_target(Vector3(400.0, 0.0, -900.0))
	var first := _rolled_context(dive_data, target)
	var second := _rolled_context(dive_data, target)
	_check(
		first.pass_dispersion_offset != Vector3.ZERO,
		"accuracy 0.3 rolls a non-zero offset"
	)
	_check(
		first.pass_dispersion_offset == second.pass_dispersion_offset,
		"identical identities reproduce the identical offset"
	)
	# Repeated ensure calls inside the same pass are stable.
	for _round in 5:
		DiveBombAttackPlanner.ensure_pass_dispersion(
			first, target, dive_data
		)
	_check(
		first.pass_dispersion_offset == second.pass_dispersion_offset,
		"re-solves inside one pass keep the offset"
	)
	# A different squadron identity produces a different roll.
	var other := DiveBombAttackContext.new()
	other.squadron_combat_id = 778
	other.reset_for_new_pass()
	DiveBombAttackPlanner.ensure_pass_dispersion(other, target, dive_data)
	_check(
		other.pass_dispersion_offset != first.pass_dispersion_offset,
		"a different squadron rolls a different offset"
	)
	# A different pass index produces a different roll.
	var next_pass := _rolled_context(dive_data, target, 2)
	_check(
		next_pass.pass_dispersion_offset != first.pass_dispersion_offset,
		"a second attack pass rolls a fresh offset"
	)
	for failure in _failures:
		push_error("DISPERSION DETERMINISM: %s" % failure)
	print(
		"DIVE_BOMB_ACCURACY_PROFILE_DETERMINISM_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _rolled_context(
		dive_data: DiveBomberCombatData,
		target: DiveBombResolvedTarget,
		passes: int = 1
) -> DiveBombAttackContext:
	var context := DiveBombAttackContext.new()
	context.squadron_combat_id = 777
	for _pass_index in passes:
		context.reset_for_new_pass()
	DiveBombAttackPlanner.ensure_pass_dispersion(context, target, dive_data)
	return context


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
