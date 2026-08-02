extends SceneTree

# Verifies the AI torpedo solution guard on TorpedoAttackController:
#   - re-aiming is allowed only during APPROACHING/ALIGNING and never once locked
#   - an update must be a newer revision of the same tracked attack, same target,
#     with valid run/arming geometry
#   - locking freezes the command so later updates are rejected.
# Drives the controller's command/state directly so no squadron or scene is
# required (the guard logic touches only the command and state).

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var controller := TorpedoAttackController.new()

	# Allowed while approaching.
	controller.command = _make_command(7, 0)
	controller.state = TorpedoAttackController.State.APPROACHING
	_check(
		controller.can_update_attack_solution(),
		"re-aim is allowed during the approach"
	)

	# Forbidden once the run has committed.
	controller.state = TorpedoAttackController.State.DESCENDING
	_check(
		not controller.can_update_attack_solution(),
		"re-aim is refused during the descent"
	)

	# A valid newer revision of the same attack is accepted.
	controller.state = TorpedoAttackController.State.APPROACHING
	controller.command = _make_command(7, 0)
	var newer := _make_command(7, 1)
	newer.entry_point = Vector3(10.0, 0.0, 0.0)
	_check(
		controller.update_attack_solution(newer),
		"a valid newer solution for the same attack is applied"
	)
	_check(
		absf(controller.command.entry_point.x - 10.0) < 0.001,
		"the applied solution replaces the command geometry"
	)
	_check(
		controller.command.solution_revision >= 1,
		"applying a solution advances the revision"
	)

	# A stale or equal revision is rejected.
	controller.command = _make_command(7, 3)
	_check(
		not controller.update_attack_solution(_make_command(7, 3)),
		"an equal-revision solution is rejected"
	)
	_check(
		not controller.update_attack_solution(_make_command(7, 2)),
		"an older-revision solution is rejected"
	)

	# A different tracked attack (or target) is rejected.
	controller.command = _make_command(7, 0)
	_check(
		not controller.update_attack_solution(_make_command(99, 1)),
		"a different tracking id is rejected"
	)

	# Invalid geometry is rejected.
	controller.command = _make_command(7, 0)
	var behind := _make_command(7, 1)
	behind.actual_release_point = Vector3(-700.0, 0.0, 0.0)
	_check(
		not controller.update_attack_solution(behind),
		"a release point behind the entry point is rejected"
	)
	var unsafe := _make_command(7, 1)
	unsafe.torpedo_safe_run_distance_m = 10.0
	_check(
		not controller.update_attack_solution(unsafe),
		"a run that would not clear the arming distance is rejected"
	)

	# Locking freezes the command.
	controller.command = _make_command(7, 0)
	controller.state = TorpedoAttackController.State.ALIGNING
	controller.solution_refresher = Callable()
	controller._finalize_and_lock_solution()
	_check(
		controller.command.solution_locked,
		"finalising locks the solution"
	)
	_check(
		not controller.can_update_attack_solution(),
		"a locked solution refuses further re-aims"
	)
	_check(
		not controller.update_attack_solution(_make_command(7, 5)),
		"no update is accepted after the solution is locked"
	)

	controller.free()

	print(
		"TORPEDO_ATTACK_SOLUTION_LOCK_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _make_command(tracking_id: int, revision: int) -> TorpedoAttackCommand:
	var command := TorpedoAttackCommand.new()
	command.tracking_id = tracking_id
	command.solution_revision = revision
	command.target_ship = null
	command.attack_direction = Vector3(1.0, 0.0, 0.0)
	command.entry_point = Vector3.ZERO
	command.actual_release_point = Vector3(700.0, 0.0, 0.0)
	command.minimum_run_distance_m = 700.0
	command.actual_run_distance_m = 700.0
	command.arming_distance_m = 50.0
	command.torpedo_safe_run_distance_m = 235.0
	return command


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO SOLUTION LOCK: %s" % label)
