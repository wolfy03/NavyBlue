extends RefCounted
class_name AIGunneryDifficultyProfileResolver

const EASY_PROFILE: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_easy.tres"
)
const NORMAL_PROFILE: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)
const HARD_PROFILE: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_hard.tres"
)

const EASY_THRESHOLD := 0.85
const HARD_THRESHOLD := 1.25

static var _warned_unknown_values: Dictionary = {}


static func resolve(difficulty_value: Variant) -> AIGunneryDifficultyProfile:
	if difficulty_value == null:
		return NORMAL_PROFILE
	if difficulty_value is int or difficulty_value is float:
		var value := float(difficulty_value)
		if is_nan(value) or is_inf(value):
			_warn_unknown_once(difficulty_value)
			return NORMAL_PROFILE
		if value < EASY_THRESHOLD:
			return EASY_PROFILE
		if value > HARD_THRESHOLD:
			return HARD_PROFILE
		return NORMAL_PROFILE
	_warn_unknown_once(difficulty_value)
	return NORMAL_PROFILE


static func _warn_unknown_once(value: Variant) -> void:
	var key := str(value)
	if _warned_unknown_values.has(key):
		return
	_warned_unknown_values[key] = true
	push_warning(
		"Unknown AI difficulty '%s'; using normal gunnery profile." % key
	)
