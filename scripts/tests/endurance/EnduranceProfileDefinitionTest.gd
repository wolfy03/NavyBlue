extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check(EnduranceProfile.validate().is_empty(), "profiles validate")
	_check(
		EnduranceProfile.get_default_frames(EnduranceProfile.SMOKE) == 600,
		"smoke uses 600 frames"
	)
	_check(
		EnduranceProfile.get_default_frames(
			EnduranceProfile.EXTENDED_SMOKE
		) == 1800,
		"extended smoke uses 1800 frames"
	)
	_check(
		EnduranceProfile.get_default_frames(
			EnduranceProfile.SEEDED_ENDURANCE
		) == 9000,
		"seeded endurance uses 9000 frames"
	)
	_check(
		EnduranceProfile.get_default_frames(
			EnduranceProfile.NIGHTLY_ENDURANCE
		) == 36000,
		"nightly endurance uses 36000 frames"
	)
	var metrics := BattleEnduranceMetrics.new()
	metrics.total_requested_frames = 1800
	metrics.total_executed_frames = 1800
	metrics.chunk_size_frames = 600
	metrics.combat_chunk_count = 3
	metrics.samples = [{}, {}, {}]
	_check(
		metrics.validate_metadata().is_empty(),
		"1800 frames with 600-frame chunks captures three chunks"
	)
	print("ENDURANCE_PROFILE_DEFINITION_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("ENDURANCE PROFILE: %s" % label)
