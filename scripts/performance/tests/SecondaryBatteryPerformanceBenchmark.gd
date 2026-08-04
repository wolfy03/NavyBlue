extends SceneTree
## Secondary battery frame-cost benchmark.
##
## Runs the same engagement under a set of isolation scenarios and prints one
## line of counters per scenario, so a bottleneck is attributed from measured
## numbers rather than guessed. Not a pass/fail functional test: absolute
## timings vary per machine, so it reports ratios and counter volumes.
##
## Scenarios (selected with NAVYBLUE_BENCH_SCENARIO):
##   baseline          everything on
##   no_secondary      secondary runtime disabled
##   no_trails         secondaries fire, trails skipped
##   no_spawn          secondaries fire, projectile instantiation skipped
##   budgeted          secondary mount evaluation budgeted across frames
## Default runs every scenario in sequence.

const STAGE: StageData = preload(
	"res://resources/stages/tests/weapon_combat_test.tres"
)
const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const DEFAULT_WARMUP_FRAMES := 120
const DEFAULT_MEASURE_FRAMES := 900

var _results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var scenarios := _resolve_scenarios()
	for scenario in scenarios:
		var result := await _run_scenario(scenario)
		_results.append(result)
	_print_report()
	quit(0)


func _resolve_scenarios() -> PackedStringArray:
	var requested := OS.get_environment("NAVYBLUE_BENCH_SCENARIO")
	if not requested.is_empty():
		return PackedStringArray([requested])
	return PackedStringArray([
		"baseline",
		"no_secondary",
		"no_trails",
		"no_spawn",
		"budgeted",
	])


func _run_scenario(scenario: String) -> Dictionary:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	var settings := BattleDebugSettings.new()
	settings.disable_secondary_battery_runtime = scenario == "no_secondary"
	settings.disable_secondary_projectile_trails = scenario == "no_trails"
	settings.disable_secondary_projectile_spawn = scenario == "no_spawn"
	settings.use_budgeted_secondary_mount_updates = scenario == "budgeted"
	battle.debug_settings = settings
	root.add_child(battle)
	await process_frame
	_close_engagement_range(battle)
	var counters := battle.battle_services.performance_counters
	counters.set_enabled(true)
	for _frame in _resolve_warmup_frames():
		await physics_frame
	counters.reset_peaks()
	var measure_frames := _resolve_measure_frames()
	var accumulator := {
		"mounts_evaluated": 0,
		"mounts_ready": 0,
		"mounts_fired": 0,
		"lead_solves": 0,
		"accuracy_solves": 0,
		"line_of_fire_checks": 0,
		"rebuilds_requested": 0,
		"rebuilds_changed": 0,
		"process_ms": 0.0,
		"physics_ms": 0.0,
		"draw_calls": 0,
		"active_projectiles": 0,
		"active_trails": 0,
	}
	var frame_times_ms := PackedFloat32Array()
	var start_usec := Time.get_ticks_usec()
	var previous_usec := start_usec
	for _frame in measure_frames:
		await physics_frame
		var now_usec := Time.get_ticks_usec()
		frame_times_ms.append(float(now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		accumulator["mounts_evaluated"] += counters.secondary_mounts_evaluated
		accumulator["mounts_ready"] += counters.secondary_mounts_ready
		accumulator["mounts_fired"] += counters.secondary_mounts_fired
		accumulator["lead_solves"] += counters.gunnery_lead_solves
		accumulator["accuracy_solves"] += counters.gunnery_accuracy_solves
		accumulator["line_of_fire_checks"] += counters.line_of_fire_checks
		accumulator["rebuilds_requested"] += \
			counters.gunnery_group_rebuilds_requested
		accumulator["rebuilds_changed"] += \
			counters.gunnery_group_rebuilds_changed
		accumulator["process_ms"] += Performance.get_monitor(
			Performance.TIME_PROCESS
		) * 1000.0
		accumulator["physics_ms"] += Performance.get_monitor(
			Performance.TIME_PHYSICS_PROCESS
		) * 1000.0
		accumulator["draw_calls"] += int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
		))
		accumulator["active_projectiles"] += counters.active_projectiles
		accumulator["active_trails"] += counters.active_trails
	var frames := float(maxi(measure_frames, 1))
	var result := {
		"scenario": scenario,
		"frames": measure_frames,
		"mount_total": counters.secondary_mounts_total,
		"evaluated_per_frame": accumulator["mounts_evaluated"] / frames,
		"ready_per_frame": accumulator["mounts_ready"] / frames,
		"fired_total": accumulator["mounts_fired"],
		"lead_per_frame": accumulator["lead_solves"] / frames,
		"accuracy_per_frame": accumulator["accuracy_solves"] / frames,
		"lof_per_frame": accumulator["line_of_fire_checks"] / frames,
		"rebuild_req_per_frame": accumulator["rebuilds_requested"] / frames,
		"rebuild_changed_per_frame": accumulator["rebuilds_changed"] / frames,
		"process_ms": accumulator["process_ms"] / frames,
		"physics_ms": accumulator["physics_ms"] / frames,
		"draw_calls": accumulator["draw_calls"] / frames,
		"projectiles_avg": accumulator["active_projectiles"] / frames,
		"trails_avg": accumulator["active_trails"] / frames,
		"projectiles_peak": counters.peak_active_projectiles,
		"trails_peak": counters.peak_active_trails,
	}
	_fill_frame_statistics(result, frame_times_ms)
	battle.shutdown()
	battle.queue_free()
	await process_frame
	await process_frame
	return result


## Secondary guns only reach ~5 km, so the stage's default separation leaves
## them idle. Pull the two sides into a broadside pass abeam of each other so
## every mount has a live firing solution.
func _close_engagement_range(battle: BattleScene) -> void:
	var friendly: Array[ShipUnit] = []
	if battle.player_ship != null:
		friendly.append(battle.player_ship)
	friendly.append_array(battle.allies)
	var index := 0
	for ship in friendly:
		if ship == null or not is_instance_valid(ship):
			continue
		ship.global_position = Vector3(-900.0, 0.0, float(index) * 400.0)
		index += 1
	index = 0
	for ship in battle.enemies:
		if ship == null or not is_instance_valid(ship):
			continue
		ship.global_position = Vector3(900.0, 0.0, float(index) * 400.0)
		index += 1


func _fill_frame_statistics(
		result: Dictionary,
		frame_times_ms: PackedFloat32Array
) -> void:
	if frame_times_ms.is_empty():
		return
	var total := 0.0
	for value in frame_times_ms:
		total += value
	var average := total / float(frame_times_ms.size())
	var sorted := frame_times_ms.duplicate()
	sorted.sort()
	var worst_count := maxi(1, int(float(sorted.size()) * 0.01))
	var worst_total := 0.0
	for index in worst_count:
		worst_total += sorted[sorted.size() - 1 - index]
	var worst_average := worst_total / float(worst_count)
	result["avg_frame_ms"] = average
	result["avg_fps"] = 1000.0 / average if average > 0.0 else 0.0
	result["one_percent_low_fps"] = 1000.0 / worst_average \
		if worst_average > 0.0 else 0.0
	result["max_frame_ms"] = sorted[sorted.size() - 1]


func _print_report() -> void:
	print("SECONDARY_BATTERY_PERFORMANCE_BENCHMARK")
	for result in _results:
		print(
			(
				"scenario=%s frames=%d mounts=%d "
				+ "avg_fps=%.1f low1%%=%.1f avg_frame_ms=%.2f max_ms=%.1f "
				+ "process_ms=%.2f physics_ms=%.2f draw=%d "
				+ "eval/f=%.1f ready/f=%.1f fired=%d "
				+ "lead/f=%.2f accuracy/f=%.2f lof/f=%.2f "
				+ "rebuild_req/f=%.2f rebuild_chg/f=%.3f "
				+ "proj_avg=%.1f proj_peak=%d trail_avg=%.1f trail_peak=%d"
			) % [
				result.get("scenario", "?"),
				int(result.get("frames", 0)),
				int(result.get("mount_total", 0)),
				float(result.get("avg_fps", 0.0)),
				float(result.get("one_percent_low_fps", 0.0)),
				float(result.get("avg_frame_ms", 0.0)),
				float(result.get("max_frame_ms", 0.0)),
				float(result.get("process_ms", 0.0)),
				float(result.get("physics_ms", 0.0)),
				int(result.get("draw_calls", 0)),
				float(result.get("evaluated_per_frame", 0.0)),
				float(result.get("ready_per_frame", 0.0)),
				int(result.get("fired_total", 0)),
				float(result.get("lead_per_frame", 0.0)),
				float(result.get("accuracy_per_frame", 0.0)),
				float(result.get("lof_per_frame", 0.0)),
				float(result.get("rebuild_req_per_frame", 0.0)),
				float(result.get("rebuild_changed_per_frame", 0.0)),
				float(result.get("projectiles_avg", 0.0)),
				int(result.get("projectiles_peak", 0)),
				float(result.get("trails_avg", 0.0)),
				int(result.get("trails_peak", 0)),
			]
		)


func _resolve_warmup_frames() -> int:
	var override := OS.get_environment("NAVYBLUE_BENCH_WARMUP_FRAMES")
	return maxi(int(override), 1) if override.is_valid_int() \
		else DEFAULT_WARMUP_FRAMES


func _resolve_measure_frames() -> int:
	var override := OS.get_environment("NAVYBLUE_BENCH_FRAMES")
	return maxi(int(override), 1) if override.is_valid_int() \
		else DEFAULT_MEASURE_FRAMES
