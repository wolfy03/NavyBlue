extends SceneTree

const SETTINGS: FleetAISettings = preload(
	"res://resources/settings/default_fleet_ai_settings.tres"
)
const NORMAL: AIDifficultyProfile = preload(
	"res://resources/ai_difficulty/normal.tres"
)
const EASY: AIDifficultyProfile = preload(
	"res://resources/ai_difficulty/easy.tres"
)
const HARD: AIDifficultyProfile = preload(
	"res://resources/ai_difficulty/hard.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check_intervals(NORMAL, [1.7, 4.0, 3.0, 1.5], "normal")
	_check_intervals(EASY, [2.2, 5.0, 4.0, 2.0], "easy")
	_check_intervals(HARD, [1.2, 3.0, 2.2, 1.0], "hard")
	print("AI_DIFFICULTY_EFFECTIVE_INTERVAL_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check_intervals(
		profile: AIDifficultyProfile,
		expected: Array,
		label: String
) -> void:
	var actual := [
		SETTINGS.fleet_update_interval_sec
			* profile.fleet_update_interval_multiplier,
		SETTINGS.role_update_interval_sec
			* profile.role_update_interval_multiplier,
		SETTINGS.tactical_update_interval_sec
			* profile.tactical_update_interval_multiplier,
		SETTINGS.cleanup_interval_sec
			* profile.cleanup_interval_multiplier,
	]
	for index in actual.size():
		_check(
			is_equal_approx(float(actual[index]), float(expected[index])),
			"%s interval %d is preserved" % [label, index]
		)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("AI DIFFICULTY INTERVAL: %s" % label)
