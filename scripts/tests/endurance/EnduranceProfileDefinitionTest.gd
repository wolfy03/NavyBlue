extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_run_checks()
	await process_frame
	await process_frame
	print("ENDURANCE_PROFILE_DEFINITION_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _run_checks() -> void:
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
	_check(
		EnduranceResultMetadata.validate(
			1800,
			1800,
			600,
			3,
			3
		).is_empty(),
		"1800 frames with 600-frame chunks captures three chunks"
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("ENDURANCE PROFILE: %s" % label)
