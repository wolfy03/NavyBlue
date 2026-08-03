extends SceneTree
## Covers: difficulty scaling, crew-skill scaling, range growth, minimum error
## floors, deterministic seeds, and statistical sanity (nonzero spread ordering
## across difficulty tiers over hundreds of samples).

const EASY: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_easy.tres"
)
const NORMAL: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)
const HARD: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_hard.tres"
)
const WEAPON_PROFILE: GunneryWeaponAccuracyProfile = preload(
	"res://resources/weapon_accuracy/default_cannon_accuracy.tres"
)
const SAMPLE_COUNT := 300

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_difficulty_scaling()
	_test_crew_scaling()
	_test_range_growth()
	_test_minimum_error_floor()
	_test_deterministic_seeds()
	_test_statistical_spread()
	_test_observation_model()
	print("GUNNERY_ACCURACY_RESOLVER_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _make_context(
		difficulty: AIGunneryDifficultyProfile,
		crew_skill: float,
		range_m: float,
		salvo_index := 0
) -> GunneryAccuracyContext:
	var context := GunneryAccuracyContext.new()
	context.shooter_instance_id = 11
	context.target_instance_id = 22
	context.fire_command_id = 1
	context.salvo_index = salvo_index
	context.weapon_group_id = &"test_cannon"
	context.launch_position = Vector3.ZERO
	context.ideal_aim_point = Vector3(0, 0, range_m)
	context.range_m = range_m
	context.weapon_accuracy_profile = WEAPON_PROFILE
	context.difficulty_profile = difficulty
	var crew := GunneryCrewStats.new()
	crew.rangefinding_skill = crew_skill
	crew.target_tracking_skill = crew_skill
	crew.fire_control_skill = crew_skill
	crew.gun_laying_skill = crew_skill
	crew.salvo_correction_skill = crew_skill
	context.crew_stats = crew
	return context


func _test_difficulty_scaling() -> void:
	var easy := GunneryAccuracyResolver.compute_sigmas(
		_make_context(EASY, 0.5, 5000.0)
	)
	var normal := GunneryAccuracyResolver.compute_sigmas(
		_make_context(NORMAL, 0.5, 5000.0)
	)
	var hard := GunneryAccuracyResolver.compute_sigmas(
		_make_context(HARD, 0.5, 5000.0)
	)
	_check(
		easy.range_sigma_m > normal.range_sigma_m
			and normal.range_sigma_m > hard.range_sigma_m,
		"difficulty: range sigma easy > normal > hard"
	)
	_check(
		easy.shell_dispersion_sigma_m > normal.shell_dispersion_sigma_m
			and normal.shell_dispersion_sigma_m > hard.shell_dispersion_sigma_m,
		"difficulty: dispersion sigma easy > normal > hard"
	)
	_check(hard.range_sigma_m > 0.0, "difficulty: hard error stays above zero")


func _test_crew_scaling() -> void:
	var poor := GunneryAccuracyResolver.compute_sigmas(
		_make_context(NORMAL, 0.0, 5000.0)
	)
	var elite := GunneryAccuracyResolver.compute_sigmas(
		_make_context(NORMAL, 1.0, 5000.0)
	)
	_check(
		poor.range_sigma_m > elite.range_sigma_m,
		"crew: poor crew has larger range sigma"
	)
	_check(
		poor.lateral_sigma_m > elite.lateral_sigma_m,
		"crew: poor crew has larger lateral sigma"
	)
	_check(
		elite.range_sigma_m > 0.0 and elite.shell_dispersion_sigma_m > 0.0,
		"crew: elite crew error stays above zero"
	)


func _test_range_growth() -> void:
	var near := GunneryAccuracyResolver.compute_sigmas(
		_make_context(NORMAL, 0.5, 2500.0)
	)
	var far := GunneryAccuracyResolver.compute_sigmas(
		_make_context(NORMAL, 0.5, 10000.0)
	)
	_check(
		far.range_sigma_m > near.range_sigma_m,
		"range: sigma grows with distance"
	)
	var capped := GunneryAccuracyResolver.compute_sigmas(
		_make_context(NORMAL, 0.5, 100000.0)
	)
	var expected_cap := WEAPON_PROFILE.base_range_error_m \
		* WEAPON_PROFILE.maximum_range_factor
	_check(
		capped.range_sigma_m <= expected_cap * 1.6 * 1.3 + 0.01,
		"range: growth respects the maximum range factor cap"
	)


func _test_minimum_error_floor() -> void:
	var tight_profile := GunneryWeaponAccuracyProfile.new()
	tight_profile.base_range_error_m = 0.0
	tight_profile.base_lateral_error_m = 0.0
	tight_profile.base_shell_dispersion_m = 0.0
	tight_profile.minimum_range_error_m = 2.0
	tight_profile.minimum_lateral_error_m = 2.0
	tight_profile.minimum_shell_dispersion_m = 1.0
	var context := _make_context(HARD, 1.0, 1000.0)
	context.weapon_accuracy_profile = tight_profile
	var sigmas := GunneryAccuracyResolver.compute_sigmas(context)
	_check(
		sigmas.range_sigma_m >= 2.0 * HARD.minimum_error_multiplier,
		"floor: range error never reaches zero"
	)
	_check(
		sigmas.shell_dispersion_sigma_m
			>= 1.0 * HARD.minimum_error_multiplier,
		"floor: dispersion never reaches zero"
	)


func _test_deterministic_seeds() -> void:
	var context := _make_context(NORMAL, 0.5, 5000.0, 3)
	var first := GunneryAccuracyResolver.create_salvo_solution(context)
	var second := GunneryAccuracyResolver.create_salvo_solution(context)
	_check(
		first.biased_salvo_center.is_equal_approx(second.biased_salvo_center),
		"determinism: same context reproduces the same salvo bias"
	)
	var shell_a := GunneryAccuracyResolver.resolve_shell_point(
		first, context, 2
	)
	var shell_b := GunneryAccuracyResolver.resolve_shell_point(
		second, context, 2
	)
	_check(
		shell_a.actual_aim_point.is_equal_approx(shell_b.actual_aim_point),
		"determinism: same shell seed reproduces the same point"
	)
	var next_salvo_context := _make_context(NORMAL, 0.5, 5000.0, 4)
	var next_salvo := GunneryAccuracyResolver.create_salvo_solution(
		next_salvo_context
	)
	_check(
		not first.biased_salvo_center.is_equal_approx(
			next_salvo.biased_salvo_center
		),
		"determinism: a new salvo index produces a different bias"
	)


func _sample_mean_abs_error(
		difficulty: AIGunneryDifficultyProfile,
		crew_skill: float
) -> float:
	var total := 0.0
	for salvo_index in SAMPLE_COUNT:
		var context := _make_context(difficulty, crew_skill, 5000.0, salvo_index)
		var solution := GunneryAccuracyResolver.create_salvo_solution(context)
		var shell := GunneryAccuracyResolver.resolve_shell_point(
			solution, context, 0
		)
		total += (shell.actual_aim_point - context.ideal_aim_point).length()
	return total / float(SAMPLE_COUNT)


func _test_statistical_spread() -> void:
	var easy_error := _sample_mean_abs_error(EASY, 0.2)
	var normal_error := _sample_mean_abs_error(NORMAL, 0.5)
	var hard_error := _sample_mean_abs_error(HARD, 0.9)
	_check(
		easy_error > normal_error and normal_error > hard_error,
		"stats: mean error easy(%.1f) > normal(%.1f) > hard(%.1f)" % [
			easy_error, normal_error, hard_error,
		]
	)
	_check(hard_error > 0.5, "stats: hard mean error is not near zero")
	var variance_seen := false
	var previous := Vector3.INF
	for salvo_index in 8:
		var context := _make_context(HARD, 0.9, 5000.0, salvo_index)
		var solution := GunneryAccuracyResolver.create_salvo_solution(context)
		if previous != Vector3.INF \
				and not solution.biased_salvo_center.is_equal_approx(previous):
			variance_seen = true
		previous = solution.biased_salvo_center
	_check(variance_seen, "stats: salvo bias varies across salvo indices")


func _test_observation_model() -> void:
	var crew := GunneryCrewStats.new()
	var actual_position := Vector3(100, 0, 4000)
	var actual_velocity := Vector3(10, 0, -4)
	var observation := GunneryAccuracyResolver.observe_target(
		actual_position, actual_velocity, 12345, NORMAL, crew, 0.5
	)
	_check(
		observation.observation_delay_sec > 0.0,
		"observation: delay is positive"
	)
	_check(
		not observation.observed_position.is_equal_approx(actual_position),
		"observation: position is not a perfect copy"
	)
	var repeat := GunneryAccuracyResolver.observe_target(
		actual_position, actual_velocity, 12345, NORMAL, crew, 0.5
	)
	_check(
		repeat.observed_position.is_equal_approx(observation.observed_position),
		"observation: deterministic for the same seed"
	)
	var low_confidence := GunneryAccuracyResolver.observe_target(
		actual_position, actual_velocity, 999, NORMAL, crew, 0.2
	)
	var high_confidence := GunneryAccuracyResolver.observe_target(
		actual_position, actual_velocity, 999, NORMAL, crew, 1.0
	)
	_check(
		low_confidence.velocity_sigma_mps > high_confidence.velocity_sigma_mps,
		"observation: low confidence inflates velocity error"
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("GUNNERY ACCURACY: %s" % label)
