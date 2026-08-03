extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	_check_profile(0.7, &"easy", "easy runtime value")
	_check_profile(1.0, &"normal", "normal runtime value")
	_check_profile(1.5, &"hard", "hard runtime value")
	_check_profile(null, &"normal", "uninitialized fallback")
	_check_profile(&"unknown", &"normal", "unknown fallback")
	print(
		"AI_GUNNERY_DIFFICULTY_RESOURCE_SELECTION_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _check_profile(value: Variant, expected: StringName, label: String) -> void:
	var profile := AIGunneryDifficultyProfileResolver.resolve(value)
	_check(
		profile != null and profile.difficulty_id == expected,
		"%s resolves to %s" % [label, expected]
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("AI GUNNERY DIFFICULTY SELECTION: %s" % label)
