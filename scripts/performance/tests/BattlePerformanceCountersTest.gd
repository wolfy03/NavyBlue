extends SceneTree
## Covers the counter contract: begin_frame resets per-frame counters without
## touching live gauges, register/unregister pairs cannot double-count, peaks
## survive frame boundaries, and a disabled counter set stays inert.

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_disabled_is_inert()
	_test_begin_frame_resets_only_frame_counters()
	_test_projectile_gauge_pairs()
	_test_trail_gauge_pairs()
	_test_peaks_and_full_reset()
	_test_snapshot_shape()
	print("BATTLE_PERFORMANCE_COUNTERS_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _make() -> BattlePerformanceCounters:
	var counters := BattlePerformanceCounters.new()
	counters.set_enabled(true)
	return counters


func _test_disabled_is_inert() -> void:
	var counters := BattlePerformanceCounters.new()
	counters.count_secondary_mount_evaluated()
	counters.register_projectile(true)
	counters.register_trail()
	counters.count_lead_solve()
	_check(
		counters.secondary_mounts_evaluated == 0
			and counters.active_projectiles == 0
			and counters.active_trails == 0
			and counters.gunnery_lead_solves == 0,
		"a disabled counter set records nothing"
	)


func _test_begin_frame_resets_only_frame_counters() -> void:
	var counters := _make()
	counters.count_secondary_mount_evaluated()
	counters.count_secondary_mount_ready()
	counters.count_secondary_mount_fired()
	counters.count_lead_solve()
	counters.count_accuracy_solve()
	counters.count_line_of_fire_check()
	counters.count_group_rebuild_requested()
	counters.count_group_rebuild_changed()
	counters.register_projectile(true)
	counters.register_trail()
	counters.begin_frame()
	_check(
		counters.secondary_mounts_evaluated == 0
			and counters.secondary_mounts_ready == 0
			and counters.secondary_mounts_fired == 0
			and counters.gunnery_lead_solves == 0
			and counters.gunnery_accuracy_solves == 0
			and counters.line_of_fire_checks == 0
			and counters.gunnery_group_rebuilds_requested == 0
			and counters.gunnery_group_rebuilds_changed == 0,
		"begin_frame clears every per-frame counter"
	)
	_check(
		counters.active_projectiles == 1 and counters.active_trails == 1,
		"begin_frame leaves live gauges untouched"
	)


func _test_projectile_gauge_pairs() -> void:
	var counters := _make()
	counters.register_projectile(true)
	counters.register_projectile(false)
	_check(
		counters.active_projectiles == 2
			and counters.active_secondary_projectiles == 1,
		"secondary projectiles are tracked separately"
	)
	counters.unregister_projectile(true)
	counters.unregister_projectile(false)
	_check(
		counters.active_projectiles == 0
			and counters.active_secondary_projectiles == 0,
		"projectile gauges return to zero after cleanup"
	)
	# An extra unregister (a double free path) must not go negative.
	counters.unregister_projectile(true)
	_check(
		counters.active_projectiles == 0
			and counters.active_secondary_projectiles == 0,
		"an unmatched unregister cannot drive a gauge negative"
	)


func _test_trail_gauge_pairs() -> void:
	var counters := _make()
	for _index in 5:
		counters.register_trail()
	_check(counters.active_trails == 5, "trail gauge counts up")
	for _index in 5:
		counters.unregister_trail()
	_check(counters.active_trails == 0, "trail gauge returns to zero")
	counters.unregister_trail()
	_check(counters.active_trails == 0, "trail gauge clamps at zero")


func _test_peaks_and_full_reset() -> void:
	var counters := _make()
	for _index in 7:
		counters.register_projectile(false)
	for _index in 7:
		counters.unregister_projectile(false)
	_check(
		counters.peak_active_projectiles == 7,
		"peak survives after the live gauge drains"
	)
	counters.reset_all()
	_check(
		counters.peak_active_projectiles == 0
			and counters.active_projectiles == 0
			and counters.secondary_mounts_total == 0,
		"reset_all clears gauges and peaks for a new battle"
	)


func _test_snapshot_shape() -> void:
	var counters := _make()
	counters.add_secondary_structure(2, 40)
	counters.add_secondary_structure(1, 22)
	counters.count_secondary_mount_evaluated()
	counters.record_frame_time(16.0)
	counters.record_frame_time(33.0)
	var snapshot := counters.make_snapshot()
	_check(
		snapshot.secondary_ships == 3 and snapshot.secondary_mounts_total == 62,
		"structure totals accumulate across batteries"
	)
	_check(
		snapshot.maximum_frame_time_ms >= 33.0,
		"the snapshot reports the worst sampled frame"
	)
	_check(
		snapshot.average_fps > 0.0 and snapshot.one_percent_low_fps > 0.0,
		"the snapshot derives fps statistics from the ring buffer"
	)
	_check(
		snapshot.one_percent_low_fps <= snapshot.average_fps + 0.001,
		"the 1%% low is never better than the average"
	)
	var text := PerformanceOverlay.build_display_text(snapshot)
	_check(
		text.contains("FPS:") and text.contains("Lead solve/frame:"),
		"the overlay renders the counter block"
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("BATTLE PERFORMANCE COUNTERS: %s" % label)
