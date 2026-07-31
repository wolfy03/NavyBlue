extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	var metrics := BattleEnduranceMetrics.new()
	metrics.configure(&"extended_smoke", 7, 120, 180)
	metrics.total_requested_frames = 1800
	metrics.total_executed_frames = 1800
	metrics.chunk_size_frames = 600
	metrics.combat_chunk_count = 3
	metrics.samples.assign([{}, {}, {}])
	_check(
		metrics.validate_metadata().is_empty(),
		"1800 frames at 600 frames per chunk produces three chunks"
	)
	var summary := metrics.get_summary()
	_check(
		int(summary.get("captured_chunk_count", 0)) == 3
			and int(summary.get("warmup_frames", 0)) == 120
			and int(summary.get("cleanup_frames", 0)) == 180,
		"result metadata preserves chunk and phase counts"
	)

	metrics.combat_chunk_count = 15
	_check(
		not metrics.validate_metadata().is_empty(),
		"mismatched documented chunk counts are rejected"
	)
	print(
		"ENDURANCE_CHUNK_COUNT_CONSISTENCY_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("ENDURANCE CHUNK COUNT: %s" % label)
