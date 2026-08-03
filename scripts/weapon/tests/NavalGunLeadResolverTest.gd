extends SceneTree
## Covers: stationary target, moving-target lead direction, faster targets and
## slower projectiles increasing lead, flight-time sanity against BallisticMath,
## and no-solution failures.

const GRAVITY := 9.8
const SHELL_SPEED := 340.0

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_stationary_target()
	_test_moving_target_leads_ahead()
	_test_faster_target_increases_lead()
	_test_slower_projectile_increases_lead()
	_test_shooter_independent_flight_time()
	_test_no_solution_out_of_reach()
	_test_invalid_inputs()
	print("NAVAL_GUN_LEAD_RESOLVER_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _test_stationary_target() -> void:
	var launch := Vector3(0, 4, 0)
	var target := Vector3(0, 0.5, 5000)
	var result := NavalGunLeadResolver.solve(
		launch, target, Vector3.ZERO, SHELL_SPEED, GRAVITY
	)
	_check(result.success, "stationary: solve succeeds")
	_check(
		result.predicted_impact_position.distance_to(target) <= 1.0,
		"stationary: aim stays on the target position"
	)
	_check(
		result.projectile_flight_time_sec > 0.0,
		"stationary: positive flight time"
	)


func _test_moving_target_leads_ahead() -> void:
	var launch := Vector3(0, 4, 0)
	var target := Vector3(0, 0.5, 5000)
	var velocity := Vector3(12.0, 0.0, 0.0)
	var result := NavalGunLeadResolver.solve(
		launch, target, velocity, SHELL_SPEED, GRAVITY
	)
	_check(result.success, "moving: solve succeeds")
	var offset := result.predicted_impact_position - target
	_check(offset.x > 1.0, "moving: lead is ahead of travel direction")
	_check(absf(offset.z) < absf(offset.x), "moving: lead mostly lateral")
	var expected_lead := velocity.x * result.projectile_flight_time_sec
	_check(
		absf(offset.x - expected_lead) \
			<= NavalGunLeadResolver.LEAD_CONVERGENCE_TOLERANCE_M \
				+ velocity.x * 0.35,
		"moving: lead distance matches velocity x flight time"
	)


func _test_faster_target_increases_lead() -> void:
	var launch := Vector3(0, 4, 0)
	var target := Vector3(0, 0.5, 5000)
	var slow := NavalGunLeadResolver.solve(
		launch, target, Vector3(8, 0, 0), SHELL_SPEED, GRAVITY
	)
	var fast := NavalGunLeadResolver.solve(
		launch, target, Vector3(20, 0, 0), SHELL_SPEED, GRAVITY
	)
	_check(slow.success and fast.success, "faster: both solve")
	_check(
		(fast.predicted_impact_position - target).length()
			> (slow.predicted_impact_position - target).length(),
		"faster target produces a longer lead"
	)


func _test_slower_projectile_increases_lead() -> void:
	var launch := Vector3(0, 4, 0)
	var target := Vector3(0, 0.5, 4000)
	var velocity := Vector3(14, 0, 0)
	var fast_shell := NavalGunLeadResolver.solve(
		launch, target, velocity, 400.0, GRAVITY
	)
	var slow_shell := NavalGunLeadResolver.solve(
		launch, target, velocity, 240.0, GRAVITY
	)
	_check(fast_shell.success and slow_shell.success, "shell speed: both solve")
	_check(
		(slow_shell.predicted_impact_position - target).length()
			> (fast_shell.predicted_impact_position - target).length(),
		"slower projectile produces a longer lead"
	)
	_check(
		slow_shell.projectile_flight_time_sec
			> fast_shell.projectile_flight_time_sec,
		"slower projectile flies longer"
	)


func _test_shooter_independent_flight_time() -> void:
	# The launch contract adds no ship velocity, so the ballistic flight time
	# must match BallisticMath for the same geometry.
	var launch := Vector3(0, 4, 0)
	var target := Vector3(0, 0.5, 5000)
	var solution := NavalGunLeadResolver.solve_ballistic_to_point(
		launch, target, SHELL_SPEED, GRAVITY
	)
	_check(solution.success, "ballistic: solves")
	var angle_value: Variant = BallisticMath.solve_low_arc_angle(
		5000.0, target.y - launch.y, SHELL_SPEED, GRAVITY
	)
	_check(angle_value != null, "ballistic: BallisticMath agrees a solution exists")
	if angle_value != null:
		_check(
			absf(solution.elevation_rad - float(angle_value)) < 0.0001,
			"ballistic: elevation matches BallisticMath.solve_low_arc_angle"
		)


func _test_no_solution_out_of_reach() -> void:
	var launch := Vector3(0, 4, 0)
	var unreachable := Vector3(0, 0.5, 100000)
	var result := NavalGunLeadResolver.solve(
		launch, unreachable, Vector3.ZERO, SHELL_SPEED, GRAVITY
	)
	_check(not result.success, "out of reach: fails")
	_check(
		result.failure_reason == &"no_ballistic_solution",
		"out of reach: reports no_ballistic_solution"
	)


func _test_invalid_inputs() -> void:
	var zero_speed := NavalGunLeadResolver.solve(
		Vector3.ZERO, Vector3(0, 0, 1000), Vector3.ZERO, 0.0, GRAVITY
	)
	_check(not zero_speed.success, "invalid: zero projectile speed fails")
	var degenerate := NavalGunLeadResolver.solve_ballistic_to_point(
		Vector3.ZERO, Vector3.ZERO, SHELL_SPEED, GRAVITY
	)
	_check(not degenerate.success, "invalid: degenerate distance fails")


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("NAVAL GUN LEAD: %s" % label)
