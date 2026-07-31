extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_run_checks()
	await process_frame
	await process_frame
	print(
		"ENDURANCE_CHUNK_COUNT_CONSISTENCY_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _run_checks() -> void:
	var validation := EnduranceResultMetadata.validate(
		1800,
		1800,
		600,
		3,
		3
	)
	_check(
		validation.is_empty(),
		"1800 frames at 600 frames per chunk produces three chunks"
	)
	var summary := EnduranceResultMetadata.build_summary(
		&"extended_smoke",
		7,
		1800,
		1800,
		600,
		3,
		3,
		0,
		0,
		0,
		120,
		180
	)
	_check(
		int(summary.get("captured_chunk_count", 0)) == 3
			and int(summary.get("warmup_frames", 0)) == 120
			and int(summary.get("cleanup_frames", 0)) == 180,
		"result metadata preserves chunk and phase counts"
	)

	validation = EnduranceResultMetadata.validate(
		1800,
		1800,
		600,
		15,
		3
	)
	_check(
		not validation.is_empty(),
		"mismatched documented chunk counts are rejected"
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("ENDURANCE CHUNK COUNT: %s" % label)
