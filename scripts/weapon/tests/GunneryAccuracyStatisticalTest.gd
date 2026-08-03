extends SceneTree

const SAMPLE_COUNT := 600
const EASY: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_easy.tres"
)
const NORMAL: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)
const HARD: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_hard.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	var easy := _sample(EASY, 0.2)
	var normal := _sample(NORMAL, 0.5)
	var hard := _sample(HARD, 0.9)
	var poor_crew := _sample(NORMAL, 0.1)
	var elite_crew := _sample(NORMAL, 0.9)
	_check(
		easy.rms >= normal.rms * 1.15
			and normal.rms >= hard.rms * 1.15,
		"RMS ordering easy %.2f > normal %.2f > hard %.2f"
			% [easy.rms, normal.rms, hard.rms]
	)
	_check(
		easy.percentile_95 > normal.percentile_95
			and normal.percentile_95 > hard.percentile_95,
		"95th percentile follows difficulty ordering"
	)
	_check(
		poor_crew.rms > elite_crew.rms * 1.15,
		"poor crew RMS %.2f exceeds elite crew %.2f"
			% [poor_crew.rms, elite_crew.rms]
	)
	_check(
		hard.rms > 0.5 and hard.minimum_seen > 0.0,
		"hard elite solution retains non-zero deterministic dispersion"
	)
	print(
		"GUNNERY_ACCURACY_STATISTICAL_TEST "
		+ "easy_rms=%.2f normal_rms=%.2f hard_rms=%.2f "
		% [easy.rms, normal.rms, hard.rms]
		+ "poor_crew_rms=%.2f elite_crew_rms=%.2f failures=%d"
		% [poor_crew.rms, elite_crew.rms, _failures.size()]
	)
	quit(0 if _failures.is_empty() else 1)


func _sample(
		difficulty: AIGunneryDifficultyProfile,
		crew_skill: float
) -> Dictionary:
	var squared_total := 0.0
	var errors: Array[float] = []
	var minimum_seen := INF
	for salvo_index in SAMPLE_COUNT:
		var context := _make_context(difficulty, crew_skill, salvo_index)
		var solution := GunneryAccuracyResolver.create_salvo_solution(context)
		var shell := GunneryAccuracyResolver.resolve_shell_point(
			solution, context, 0
		)
		var error := shell.actual_aim_point.distance_to(
			context.ideal_aim_point
		)
		errors.append(error)
		squared_total += error * error
		minimum_seen = minf(minimum_seen, error)
	errors.sort()
	return {
		"rms": sqrt(squared_total / float(SAMPLE_COUNT)),
		"percentile_95": errors[floori(float(SAMPLE_COUNT - 1) * 0.95)],
		"minimum_seen": minimum_seen,
	}


func _make_context(
		difficulty: AIGunneryDifficultyProfile,
		crew_skill: float,
		salvo_index: int
) -> GunneryAccuracyContext:
	var context := GunneryAccuracyContext.new()
	context.shooter_instance_id = 101
	context.target_instance_id = 202
	context.fire_command_id = 3
	context.salvo_index = salvo_index
	context.weapon_group_id = &"statistical_cannon"
	context.launch_position = Vector3.ZERO
	context.ideal_aim_point = Vector3(0.0, 0.0, 5000.0)
	context.range_m = 5000.0
	context.weapon_accuracy_profile = \
		GunneryAccuracyProfileResolver.SHARED_DEFAULT
	context.difficulty_profile = difficulty
	var crew := GunneryCrewStats.new()
	crew.rangefinding_skill = crew_skill
	crew.target_tracking_skill = crew_skill
	crew.fire_control_skill = crew_skill
	crew.gun_laying_skill = crew_skill
	crew.salvo_correction_skill = crew_skill
	context.crew_stats = crew
	return context


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("GUNNERY STATISTICS: %s" % label)
