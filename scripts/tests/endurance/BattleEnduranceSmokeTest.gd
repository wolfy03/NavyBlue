extends SceneTree

const BATTLE_LOOP_STAGE: StageData = preload(
	"res://resources/stages/tests/battle_loop_test.tres"
)


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var packed := load(
		"res://scenes/world/battle_scene.tscn"
	) as PackedScene
	if packed == null:
		push_error("ENDURANCE: battle scene failed to load.")
		quit(1)
		return
	var scene := packed.instantiate() as BattleScene
	scene.stage_override = BATTLE_LOOP_STAGE
	root.add_child(scene)
	await process_frame
	await physics_frame
	if not scene.initialization_result.success:
		push_error("ENDURANCE: battle scene initialization failed.")
		quit(1)
		return

	var profile_name := _resolve_profile_name()
	var frame_count := _resolve_frame_count(profile_name)
	var seed_value := _resolve_seed()
	seed(seed_value)
	var services := scene.battle_services
	var metrics := BattleEnduranceMetrics.new()
	metrics.configure(
		profile_name,
		seed_value,
		EnduranceProfile.DEFAULT_WARMUP_FRAMES,
		EnduranceProfile.DEFAULT_CLEANUP_FRAMES
	)
	var runner := BattleEnduranceRunner.new()
	await runner.wait_frames(self, metrics.warmup_frames)
	metrics.capture_baseline(self, services)
	await runner.run(
		self,
		frame_count,
		metrics,
		services,
		EnduranceProfile.DEFAULT_CHUNK_SIZE_FRAMES
	)
	var failures := metrics.validate_metadata()
	# Class-based secondary batteries can put dozens of legitimate shells and
	# their trail nodes in flight together. Active-combat headroom reflects the
	# 30-mount battleship layout; post-cleanup counts remain strictly zero.
	failures.append_array(metrics.validate_bounded_growth(320, 96, 16))

	scene.shutdown()
	scene.queue_free()
	await runner.wait_frames(self, metrics.cleanup_frames)
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.call(&"clear_pool")
	await process_frame
	await process_frame
	await physics_frame
	metrics.capture_post_cleanup(self, services)
	failures.append_array(metrics.validate_cleanup())

	var summary := metrics.get_summary()
	print(
		"BATTLE_ENDURANCE profile=%s frames=%d seed=%d summary=%s failures=%d"
		% [
			profile_name,
			frame_count,
			seed_value,
			summary,
			failures.size(),
		]
	)
	for failure in failures:
		push_error("BATTLE_ENDURANCE: %s" % failure)
	if not _write_result(summary, failures):
		failures.append("Endurance result file could not be written.")
	quit(0 if failures.is_empty() else 1)


func _resolve_profile_name() -> StringName:
	var value := StringName(OS.get_environment(
		"NAVYBLUE_ENDURANCE_PROFILE"
	))
	return value if EnduranceProfile.get_default_frames(value) > 0 \
		else EnduranceProfile.SMOKE


func _resolve_frame_count(profile_name: StringName) -> int:
	var override := OS.get_environment("NAVYBLUE_ENDURANCE_FRAMES")
	return maxi(int(override), 1) if override.is_valid_int() \
		else EnduranceProfile.get_default_frames(profile_name)


func _resolve_seed() -> int:
	var value := OS.get_environment("NAVYBLUE_ENDURANCE_SEED")
	return int(value) if value.is_valid_int() else 1


func _write_result(
		summary: Dictionary,
		failures: PackedStringArray
) -> bool:
	var output_path := OS.get_environment("NAVYBLUE_ENDURANCE_OUTPUT_PATH")
	if output_path.is_empty():
		return true
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"profile": String(summary.get(
			"profile_name",
			EnduranceProfile.SMOKE
		)),
		"frames": int(summary.get("total_executed_frames", 0)),
		"seed": int(summary.get("seed", 1)),
		"success": failures.is_empty(),
		"metrics": summary,
		"failures": Array(failures),
	}, "\t"))
	file.close()
	return true
