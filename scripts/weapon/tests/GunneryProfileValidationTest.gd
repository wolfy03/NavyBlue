extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	_test_difficulty_validation_and_runtime_sanitize()
	_test_crew_validation_and_runtime_sanitize()
	_test_weapon_profile_validation_and_fallback()
	print("GUNNERY_PROFILE_VALIDATION_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _test_difficulty_validation_and_runtime_sanitize() -> void:
	var difficulty := AIGunneryDifficultyProfile.new()
	difficulty.range_error_multiplier = -2.0
	difficulty.lateral_error_multiplier = -3.0
	difficulty.shell_dispersion_multiplier = -4.0
	difficulty.minimum_observation_delay_sec = -1.0
	difficulty.maximum_observation_delay_sec = -2.0
	difficulty.base_salvo_correction_strength = 4.0
	difficulty.minimum_corrected_bias_ratio = -1.0
	_check(
		difficulty.validate().size() >= 6,
		"difficulty validation rejects malformed external values"
	)
	var context := _make_context(difficulty, GunneryCrewStats.new())
	var result := GunneryAccuracyResolver.compute_sigmas(context)
	_check(
		result.success
			and result.range_sigma_m > 0.0
			and result.lateral_sigma_m > 0.0
			and result.shell_dispersion_sigma_m > 0.0
			and is_finite(result.range_sigma_m),
		"difficulty runtime sanitize prevents negative or non-finite sigma"
	)


func _test_crew_validation_and_runtime_sanitize() -> void:
	var crew := GunneryCrewStats.new()
	crew.rangefinding_skill = -4.0
	crew.target_tracking_skill = 8.0
	crew.fire_control_skill = -2.0
	crew.gun_laying_skill = 9.0
	crew.salvo_correction_skill = -1.0
	_check(
		crew.validate().size() == 5,
		"crew validation checks every normalized skill"
	)
	var result := GunneryAccuracyResolver.compute_sigmas(
		_make_context(AIGunneryDifficultyProfile.new(), crew)
	)
	_check(
		result.success
			and result.range_sigma_m > 0.0
			and result.shell_dispersion_sigma_m > 0.0,
		"crew runtime sanitize clamps restored values"
	)


func _test_weapon_profile_validation_and_fallback() -> void:
	var malformed := GunneryWeaponAccuracyProfile.new()
	malformed.reference_range_m = 0.0
	malformed.base_range_error_m = -1.0
	malformed.range_error_growth_exponent = -1.0
	malformed.minimum_range_factor = 0.0
	malformed.maximum_range_factor = -1.0
	malformed.minimum_range_error_m = 0.0
	malformed.minimum_lateral_error_m = 0.0
	malformed.minimum_shell_dispersion_m = 0.0
	_check(
		malformed.validate().size() >= 6,
		"weapon profile validation covers range, growth, factors, and floors"
	)
	var resolved := GunneryAccuracyProfileResolver.resolve(malformed)
	_check(
		resolved == GunneryAccuracyProfileResolver.SHARED_DEFAULT,
		"malformed weapon profile uses the shared validated default"
	)
	var fallback_a := GunneryAccuracyProfileResolver.resolve(null, null)
	var fallback_b := GunneryAccuracyProfileResolver.resolve(null, null)
	_check(
		fallback_a == fallback_b and fallback_a.validate().is_empty(),
		"code fallback is valid and allocated only once"
	)


func _make_context(
		difficulty: AIGunneryDifficultyProfile,
		crew: GunneryCrewStats
) -> GunneryAccuracyContext:
	var context := GunneryAccuracyContext.new()
	context.launch_position = Vector3.ZERO
	context.ideal_aim_point = Vector3(0.0, 0.0, 5000.0)
	context.range_m = 5000.0
	context.weapon_accuracy_profile = \
		GunneryAccuracyProfileResolver.SHARED_DEFAULT
	context.difficulty_profile = difficulty
	context.crew_stats = crew
	return context


func is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("GUNNERY PROFILE VALIDATION: %s" % label)
