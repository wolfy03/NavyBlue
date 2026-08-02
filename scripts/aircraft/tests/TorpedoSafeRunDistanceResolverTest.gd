extends SceneTree

# Verifies TorpedoSafeRunDistanceResolver builds a torpedo release distance that
# guarantees the torpedo is armed before it reaches the hull. Exercises the pure
# composition math and the margin helpers without a ship or scene:
#   - minimum safe run = arming + collision + prediction + additional
#   - the armed underwater run to the hull is never below the arming distance
#   - the airborne fall distance is tracked separately (not counted as arming)
#   - a preferred-run ceiling that would starve arming is rejected
#   - prediction-error and airborne-travel helpers scale as expected.

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	# arming 120, collision 20, prediction 15, additional 100 -> minimum 255.
	var airborne := 147.0
	var result := TorpedoSafeRunDistanceResolver.compose(
		120.0, 20.0, 15.0, 100.0, airborne, 0.0, 0.0
	)
	_check(result.success, "a well-formed request succeeds")
	_check(
		absf(result.minimum_safe_run_distance_m - 255.0) < 0.001,
		"minimum safe run distance sums the four margins (>= 255)"
	)
	_check(
		result.minimum_safe_run_distance_m >= 255.0,
		"minimum safe run distance is at least 255 m"
	)
	_check(
		absf(result.preferred_run_distance_m - 255.0) < 0.001,
		"preferred run distance defaults to the minimum safe run"
	)
	_check(
		absf(result.release_offset_from_center_m - (airborne + 255.0)) < 0.001,
		"release offset adds the airborne travel to the underwater run"
	)
	_check(
		result.underwater_run_to_hull_m >= result.arming_distance_m,
		"the armed underwater run clears the arming distance"
	)
	_check(
		absf(result.underwater_run_to_hull_m - 235.0) < 0.001,
		"underwater run to the hull is the preferred run minus collision margin"
	)
	_check(
		result.airborne_travel_margin_m > 0.0,
		"airborne travel is tracked and not folded into the arming run"
	)

	# A preferred-run ceiling below the arming requirement is a hard failure.
	var starved := TorpedoSafeRunDistanceResolver.compose(
		120.0, 20.0, 15.0, 100.0, airborne, 0.0, 200.0
	)
	_check(
		not starved.success,
		"a run-distance ceiling below the safe minimum is rejected"
	)
	_check(
		starved.failure_reason == &"preferred_run_distance_below_arming_requirement",
		"the ceiling rejection reports the arming-requirement reason"
	)

	# A ceiling at or above the minimum simply clamps.
	var capped := TorpedoSafeRunDistanceResolver.compose(
		120.0, 20.0, 15.0, 100.0, airborne, 0.0, 300.0
	)
	_check(
		capped.success and absf(capped.preferred_run_distance_m - 255.0) < 0.001,
		"a ceiling above the minimum leaves the preferred run at the minimum"
	)

	# A tactical floor raises the preferred run above the safe minimum.
	var floored := TorpedoSafeRunDistanceResolver.compose(
		120.0, 20.0, 15.0, 100.0, airborne, 400.0, 0.0
	)
	_check(
		floored.success and absf(floored.preferred_run_distance_m - 400.0) < 0.001,
		"a preferred-run floor above the minimum is honoured"
	)
	_check(
		absf(floored.underwater_run_to_hull_m - 380.0) < 0.001,
		"the floored underwater run still subtracts the collision margin"
	)

	# Prediction-error margin scales with target speed, interval, and factor.
	var margin := TorpedoSafeRunDistanceResolver.prediction_error_margin(
		40.0, 0.5, 1.25
	)
	_check(absf(margin - 25.0) < 0.001, "prediction-error margin is speed*interval*factor")
	_check(
		TorpedoSafeRunDistanceResolver.prediction_error_margin(0.0, 0.5, 1.25) == 0.0,
		"a stationary target has no prediction-error margin"
	)

	# Airborne travel scales with drop speed and fall time.
	var travel := TorpedoSafeRunDistanceResolver.airborne_travel_distance(
		65.0, 25.0, 9.8
	)
	_check(
		travel > 100.0 and travel < 200.0,
		"airborne travel over a 25 m drop at 65 m/s is roughly 140-150 m"
	)
	var faster_travel := TorpedoSafeRunDistanceResolver.airborne_travel_distance(
		90.0, 25.0, 9.8
	)
	_check(faster_travel > travel, "a faster drop covers more airborne distance")

	print(
		"TORPEDO_SAFE_RUN_DISTANCE_RESOLVER_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO SAFE RUN: %s" % label)
