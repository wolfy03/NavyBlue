extends SceneTree
## Guards against double target-lead in the dive bomb pipeline (spec: the
## time-to-impact lead is composed exactly once, in the intended impact point;
## the bomb's launch velocity comes only from the aircraft's flight state).

const GRAVITY := 9.8
const TARGET_VELOCITY := Vector3(14.0, 0.0, 6.0)

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var dive_data := DiveBomberCombatData.new()
	var weapon_data := _load_bomb_weapon_data()
	if weapon_data == null:
		_failures.append("basic bomber weapon data loads")
	else:
		_test_lead_composed_once(dive_data, weapon_data)
		_test_bomb_velocity_ignores_target(weapon_data)
		_test_trajectory_independent_of_target_velocity(
			dive_data, weapon_data
		)
	print(
		"DIVE_BOMB_NO_DOUBLE_LEAD_TEST failures=%d" % _failures.size()
	)
	for failure in _failures:
		push_error("DIVE BOMB NO DOUBLE LEAD: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


## The intended impact point must be exactly target + v * (dive + fall time):
## the lead appears once, with the full time budget, and nowhere else.
func _test_lead_composed_once(
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData
) -> void:
	var reference_position := Vector3(0.0, dive_data.dive_entry_altitude_m, 0.0)
	var target_position := Vector3(0.0, 0.0, 2000.0)
	var solution := DiveBombAttackResolver.solve_from_current_dive_state(
		reference_position,
		target_position,
		TARGET_VELOCITY,
		0.0,
		dive_data,
		weapon_data,
		GRAVITY
	)
	if solution == null or not solution.valid:
		_failures.append("moving-target current-state solve succeeds")
		return
	var expected := target_position + TARGET_VELOCITY * (
		solution.dive_time_to_release_sec + solution.bomb_fall_time_sec
	)
	expected.y = 0.0
	var error := (
		solution.exact_intended_impact_position - expected
	).length()
	if error > 0.01:
		_failures.append(
			"intended impact must equal target + v*t exactly once "
			+ "(off by %.3f m)" % error
		)
	if solution.final_aim_impact_position \
			!= solution.exact_intended_impact_position:
		_failures.append(
			"with zero dispersion the final aim equals the exact intended point"
		)


## The launch contract takes only the aircraft's velocity: there is no
## parameter through which target motion could leak into the bomb velocity.
func _test_bomb_velocity_ignores_target(
		weapon_data: AircraftWeaponData
) -> void:
	var aircraft_velocity := Vector3(120.4, -172.0, 0.0)
	var bomb_velocity := DiveBombBallistics.resolve_bomb_initial_velocity(
		aircraft_velocity,
		weapon_data
	)
	if Vector3(bomb_velocity.x, 0.0, bomb_velocity.z) \
			!= Vector3(aircraft_velocity.x, 0.0, aircraft_velocity.z):
		_failures.append(
			"bomb horizontal velocity is exactly the aircraft's"
		)
	if bomb_velocity.y > aircraft_velocity.y + 0.001:
		_failures.append(
			"bomb vertical velocity keeps the dive's downward speed"
		)


## Same reference, same dive: target motion moves WHERE we aim (the intended
## point rotates the attack direction) but must not stretch the trajectory
## itself - dive distance and bomb travel stay those of the fixed dive
## geometry, or the lead would be applied a second time through the path.
func _test_trajectory_independent_of_target_velocity(
		dive_data: DiveBomberCombatData,
		weapon_data: AircraftWeaponData
) -> void:
	var reference_position := Vector3(0.0, dive_data.dive_entry_altitude_m, 0.0)
	var target_position := Vector3(0.0, 0.0, 2000.0)
	var static_solution := DiveBombAttackResolver.solve_from_current_dive_state(
		reference_position,
		target_position,
		Vector3.ZERO,
		0.0,
		dive_data,
		weapon_data,
		GRAVITY
	)
	var moving_solution := DiveBombAttackResolver.solve_from_current_dive_state(
		reference_position,
		target_position,
		TARGET_VELOCITY,
		0.0,
		dive_data,
		weapon_data,
		GRAVITY
	)
	if static_solution == null or not static_solution.valid \
			or moving_solution == null or not moving_solution.valid:
		_failures.append("both static and moving solves succeed")
		return
	if absf(
		static_solution.horizontal_dive_distance_m
			- moving_solution.horizontal_dive_distance_m
	) > 0.01:
		_failures.append(
			"target motion must not change the dive's horizontal distance"
		)
	if absf(
		static_solution.bomb_horizontal_travel_m
			- moving_solution.bomb_horizontal_travel_m
	) > 0.01:
		_failures.append(
			"target motion must not change the bomb's horizontal travel"
		)
	if absf(
		static_solution.total_time_to_impact_sec
			- moving_solution.total_time_to_impact_sec
	) > 0.001:
		_failures.append(
			"target motion must not change the time to impact"
		)
	# At commit geometry (reference exactly one dive + one bomb-travel from
	# the aim) the fixed trajectory must drop the bomb ON the aim point. Any
	# second application of lead would shift the trajectory impact off it.
	var required_travel := moving_solution.horizontal_dive_distance_m \
		+ moving_solution.bomb_horizontal_travel_m
	var aim := moving_solution.final_aim_impact_position
	var back_direction := (reference_position - aim)
	back_direction.y = 0.0
	back_direction = back_direction.normalized()
	var commit_position := aim + back_direction * required_travel
	commit_position.y = reference_position.y
	var commit_solution := DiveBombAttackResolver.solve_from_current_dive_state(
		commit_position,
		target_position,
		TARGET_VELOCITY,
		0.0,
		dive_data,
		weapon_data,
		GRAVITY
	)
	if commit_solution == null or not commit_solution.valid:
		_failures.append("commit-distance solve succeeds")
		return
	var trajectory_error := (
		commit_solution.trajectory_predicted_impact_position
			- commit_solution.final_aim_impact_position
	)
	trajectory_error.y = 0.0
	if trajectory_error.length() > 1.0:
		_failures.append(
			"at commit distance the trajectory lands on the aim point "
			+ "(off by %.2f m)" % trajectory_error.length()
		)


func _load_bomb_weapon_data() -> AircraftWeaponData:
	var aircraft_data := load(
		"res://resources/aircraft/types/basic_dive_bomber.tres"
	) as AircraftData
	return aircraft_data.weapon_data if aircraft_data != null else null
