extends SceneTree

# Verifies the AI dive-bomb solution lock on DiveBombAttackController:
#   - while the solution is open, update_target moves the aim point (player dives)
#   - once locked (AI dive committed), update_target is ignored so the flight
#     bombs a fixed point instead of chasing the ship
#   - update_target still respects the valid dive states.
# Drives target/state directly so no squadron or scene is needed.

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var controller := DiveBombAttackController.new()

	# Open solution (player-style): tracking is honoured.
	controller.state = DiveBombAttackController.State.DIVING
	controller.solution_locked = false
	controller.update_target(Vector3(1.0, 0.0, 3.0), Vector3(2.0, 0.0, 0.0))
	_check(
		controller.target_position.is_equal_approx(Vector3(1.0, 0.0, 3.0)),
		"an open solution accepts target updates"
	)
	_check(
		controller.target_velocity.is_equal_approx(Vector3(2.0, 0.0, 0.0)),
		"an open solution accepts velocity updates"
	)

	# Locked solution (AI committed): further tracking is ignored.
	controller.solution_locked = true
	_check(controller.is_solution_locked(), "is_solution_locked reflects the lock")
	controller.update_target(Vector3(9.0, 0.0, 9.0), Vector3(5.0, 0.0, 0.0))
	_check(
		controller.target_position.is_equal_approx(Vector3(1.0, 0.0, 3.0)),
		"a locked solution freezes the impact point"
	)
	_check(
		controller.target_velocity.is_equal_approx(Vector3(2.0, 0.0, 0.0)),
		"a locked solution freezes the target velocity"
	)

	# Outside the dive states, updates are ignored even when open.
	controller.solution_locked = false
	controller.state = DiveBombAttackController.State.IDLE
	controller.update_target(Vector3(7.0, 0.0, 7.0), Vector3.ZERO)
	_check(
		controller.target_position.is_equal_approx(Vector3(1.0, 0.0, 3.0)),
		"updates are ignored outside the active dive states"
	)

	controller.free()

	print(
		"DIVE_BOMB_SOLUTION_LOCK_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("DIVE BOMB SOLUTION LOCK: %s" % label)
