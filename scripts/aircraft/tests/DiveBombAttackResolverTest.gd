extends SceneTree
## Covers the dive-bomb attack geometry: impact/release/entry/approach
## ordering, dive and bomb travel accounting, moving-target lead, bomb velocity
## inheritance, determinism, and invalid-input handling.

const GRAVITY := 9.8

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_static_target()
	_test_release_and_entry_ordering()
	_test_dive_travel_accounted()
	_test_moving_target_leads_ahead()
	_test_crossing_target()
	_test_faster_bomb_moves_release_back()
	_test_bomb_velocity_inheritance_matches_launch_contract()
	_test_round_trip_impact_prediction()
	_test_determinism()
	_test_invalid_inputs()
	print("DIVE_BOMB_ATTACK_RESOLVER_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _make_dive_data() -> DiveBomberCombatData:
	var data := DiveBomberCombatData.new()
	data.dive_entry_altitude_m = 350.0
	data.dive_angle_degrees = 55.0
	data.dive_speed_mps = 210.0
	data.approach_distance_m = 900.0
	data.automatic_release_altitude_m = 90.0
	return data


func _make_weapon_data() -> AircraftWeaponData:
	var data := AircraftWeaponData.new()
	data.downward_release_speed_mps = 20.0
	data.release_interval_sec = 0.0
	return data


func _solve(
		target_position: Vector3,
		target_velocity: Vector3,
		attack_direction: Vector3 = Vector3.FORWARD
) -> DiveBombAttackSolution:
	return DiveBombAttackResolver.solve(
		Vector3(0.0, 350.0, -3000.0),
		Vector3.FORWARD,
		140.0,
		target_position,
		target_velocity,
		target_position.y,
		_make_dive_data(),
		_make_weapon_data(),
		GRAVITY,
		attack_direction
	)


func _test_static_target() -> void:
	var target := Vector3(0.0, 0.0, 0.0)
	var solution := _solve(target, Vector3.ZERO)
	_check(solution.valid, "static: solves")
	_check(
		solution.predicted_impact_position.distance_to(target) <= 0.01,
		"static: impact stays on the stationary target"
	)
	_check(
		solution.bomb_fall_time_sec > 0.0
			and solution.dive_time_to_release_sec > 0.0,
		"static: both dive and fall times are positive"
	)


## The core geometry contract: release is short of the impact point, and the
## dive starts short of the release point, both along the attack heading.
func _test_release_and_entry_ordering() -> void:
	var direction := Vector3(0.0, 0.0, 1.0)
	var solution := _solve(Vector3.ZERO, Vector3.ZERO, direction)
	_check(solution.valid, "ordering: solves")
	var impact := solution.predicted_impact_position
	var release := solution.release_position
	var entry := solution.dive_entry_position
	var approach := solution.approach_position
	_check(
		(impact - release).dot(direction) > 0.0,
		"ordering: release is behind the impact point"
	)
	_check(
		(release - entry).dot(direction) > 0.0,
		"ordering: dive entry is behind the release point"
	)
	_check(
		(entry - approach).dot(direction) > 0.0,
		"ordering: approach is behind the dive entry"
	)
	_check(
		is_equal_approx(release.y, 90.0),
		"ordering: release sits at the automatic release altitude"
	)
	_check(
		is_equal_approx(entry.y, 350.0),
		"ordering: dive entry sits at the dive entry altitude"
	)


func _test_dive_travel_accounted() -> void:
	var solution := _solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 1))
	_check(
		solution.horizontal_dive_distance_m > 0.0,
		"dive travel: the dive covers horizontal distance"
	)
	# 350 -> 90 m at 55 degrees and 210 m/s: ~1.51 s of dive, ~182 m of travel.
	var expected := 210.0 * cos(deg_to_rad(55.0)) \
		* (260.0 / (210.0 * sin(deg_to_rad(55.0))))
	_check(
		absf(solution.horizontal_dive_distance_m - expected) < 1.0,
		"dive travel: matches speed x dive time (%.1f vs %.1f)"
			% [solution.horizontal_dive_distance_m, expected]
	)
	_check(
		solution.bomb_horizontal_travel_m > 0.0,
		"dive travel: the bomb also travels horizontally after release"
	)
	# Horizontal component only: the entry->release vector also spans the
	# 260 m descent.
	var entry_to_release := solution.release_position \
		- solution.dive_entry_position
	var horizontal_gap := Vector2(
		entry_to_release.x,
		entry_to_release.z
	).length()
	_check(
		absf(horizontal_gap - solution.horizontal_dive_distance_m) < 1.0,
		"dive travel: entry->release horizontal gap equals the dive travel"
	)


func _test_moving_target_leads_ahead() -> void:
	var velocity := Vector3(10.0, 0.0, 0.0)
	var solution := _solve(Vector3.ZERO, velocity, Vector3(0, 0, 1))
	_check(solution.valid, "moving: solves")
	_check(
		solution.predicted_impact_position.x > 0.0,
		"moving: impact leads along the target's travel direction"
	)
	_check(
		solution.total_time_to_impact_sec > solution.bomb_fall_time_sec,
		"moving: total time exceeds bomb fall time alone"
	)
	# The lead must cover dive + fall, not just the fall.
	var minimum_lead := velocity.x * (
		solution.dive_time_to_release_sec + solution.bomb_fall_time_sec
	)
	_check(
		solution.predicted_impact_position.x >= minimum_lead - 1.0,
		"moving: lead covers dive and fall time (%.1f >= %.1f)"
			% [solution.predicted_impact_position.x, minimum_lead]
	)


func _test_crossing_target() -> void:
	# Target crossing perpendicular to the attack heading: the clearest case.
	var solution := _solve(
		Vector3.ZERO,
		Vector3(18.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0)
	)
	_check(solution.valid, "crossing: solves")
	_check(
		solution.predicted_impact_position.x > 30.0,
		"crossing: impact is displaced well along the crossing axis (%.1f)"
			% solution.predicted_impact_position.x
	)
	_check(
		absf(solution.release_position.x
			- solution.predicted_impact_position.x) < 1.0,
		"crossing: release shares the impact's crossing offset"
	)


func _test_faster_bomb_moves_release_back() -> void:
	var slow_dive := _make_dive_data()
	slow_dive.dive_speed_mps = 120.0
	var fast_dive := _make_dive_data()
	fast_dive.dive_speed_mps = 260.0
	var slow := DiveBombAttackResolver.solve(
		Vector3(0.0, 350.0, -3000.0), Vector3.FORWARD, 140.0,
		Vector3.ZERO, Vector3.ZERO, 0.0,
		slow_dive, _make_weapon_data(), GRAVITY, Vector3(0, 0, 1)
	)
	var fast := DiveBombAttackResolver.solve(
		Vector3(0.0, 350.0, -3000.0), Vector3.FORWARD, 140.0,
		Vector3.ZERO, Vector3.ZERO, 0.0,
		fast_dive, _make_weapon_data(), GRAVITY, Vector3(0, 0, 1)
	)
	_check(slow.valid and fast.valid, "bomb speed: both solve")
	_check(
		fast.bomb_horizontal_travel_m > slow.bomb_horizontal_travel_m,
		"bomb speed: a faster dive throws the bomb further"
	)
	_check(
		fast.release_position.z < slow.release_position.z,
		"bomb speed: a faster bomb must be released earlier"
	)


func _test_bomb_velocity_inheritance_matches_launch_contract() -> void:
	var weapon := _make_weapon_data()
	# Mirrors AircraftWeaponController._spawn_projectile.
	var aircraft_velocity := Vector3(30.0, -5.0, 120.0)
	var bomb := DiveBombBallistics.resolve_bomb_initial_velocity(
		aircraft_velocity,
		weapon
	)
	_check(
		is_equal_approx(bomb.x, 30.0) and is_equal_approx(bomb.z, 120.0),
		"inheritance: horizontal velocity is inherited unchanged"
	)
	_check(
		is_equal_approx(bomb.y, -20.0),
		"inheritance: vertical velocity is forced to the downward release speed"
	)
	var already_fast := DiveBombBallistics.resolve_bomb_initial_velocity(
		Vector3(0.0, -80.0, 0.0),
		weapon
	)
	_check(
		is_equal_approx(already_fast.y, -80.0),
		"inheritance: a steeper dive keeps its own faster descent"
	)


## Closing the loop: feeding the planned release state back through the
## forward predictor must land on the planned impact point.
func _test_round_trip_impact_prediction() -> void:
	var solution := _solve(
		Vector3.ZERO,
		Vector3(8.0, 0.0, 0.0),
		Vector3(0, 0, 1)
	)
	_check(solution.valid, "round trip: solves")
	var predicted := DiveBombBallistics.predict_impact_from_release_state(
		solution.release_position,
		solution.predicted_bomb_velocity,
		0.0,
		_make_weapon_data(),
		GRAVITY
	)
	var error := Vector2(
		predicted.x - solution.predicted_impact_position.x,
		predicted.z - solution.predicted_impact_position.z
	).length()
	_check(
		error < 0.5,
		"round trip: forward prediction reproduces the planned impact (%.2f m)"
			% error
	)


func _test_determinism() -> void:
	var first := _solve(Vector3.ZERO, Vector3(9.0, 0.0, 3.0))
	var second := _solve(Vector3.ZERO, Vector3(9.0, 0.0, 3.0))
	_check(
		first.predicted_impact_position.is_equal_approx(
			second.predicted_impact_position
		)
			and first.release_position.is_equal_approx(second.release_position),
		"determinism: identical inputs produce an identical solution"
	)
	var drifting := _solve(Vector3.ZERO, Vector3(0.02, 0.0, 0.0))
	var stationary := _solve(Vector3.ZERO, Vector3.ZERO)
	_check(
		drifting.predicted_impact_position.is_equal_approx(
			stationary.predicted_impact_position
		),
		"determinism: sub-threshold drift is treated as stationary"
	)


func _test_invalid_inputs() -> void:
	var no_dive := DiveBombAttackResolver.solve(
		Vector3.ZERO, Vector3.FORWARD, 100.0, Vector3(0, 0, 500),
		Vector3.ZERO, 0.0, null, _make_weapon_data(), GRAVITY
	)
	_check(
		not no_dive.valid and no_dive.failure_reason == &"missing_dive_data",
		"invalid: missing dive data is reported"
	)
	var no_weapon := DiveBombAttackResolver.solve(
		Vector3.ZERO, Vector3.FORWARD, 100.0, Vector3(0, 0, 500),
		Vector3.ZERO, 0.0, _make_dive_data(), null, GRAVITY
	)
	_check(
		not no_weapon.valid
			and no_weapon.failure_reason == &"missing_weapon_data",
		"invalid: missing weapon data is reported"
	)
	var bad_gravity := DiveBombAttackResolver.solve(
		Vector3.ZERO, Vector3.FORWARD, 100.0, Vector3(0, 0, 500),
		Vector3.ZERO, 0.0, _make_dive_data(), _make_weapon_data(), 0.0
	)
	_check(
		not bad_gravity.valid
			and bad_gravity.failure_reason == &"invalid_gravity",
		"invalid: non-positive gravity is reported"
	)
	var bad_geometry_data := _make_dive_data()
	bad_geometry_data.dive_entry_altitude_m = 50.0
	var bad_geometry := DiveBombAttackResolver.solve(
		Vector3.ZERO, Vector3.FORWARD, 100.0, Vector3(0, 0, 500),
		Vector3.ZERO, 0.0, bad_geometry_data, _make_weapon_data(), GRAVITY
	)
	_check(
		not bad_geometry.valid
			and bad_geometry.failure_reason == &"invalid_dive_geometry",
		"invalid: an entry altitude below release altitude is reported"
	)
	var zero_speed_data := _make_dive_data()
	zero_speed_data.dive_speed_mps = 0.0
	var zero_speed := DiveBombAttackResolver.solve(
		Vector3.ZERO, Vector3.FORWARD, 100.0, Vector3(0, 0, 500),
		Vector3.ZERO, 0.0, zero_speed_data, _make_weapon_data(), GRAVITY
	)
	_check(
		not zero_speed.valid
			and zero_speed.failure_reason == &"invalid_dive_speed",
		"invalid: zero dive speed is reported"
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("DIVE BOMB RESOLVER: %s" % label)
