extends SceneTree

const BATTLE_LOOP_STAGE: StageData = preload(
	"res://resources/stages/tests/battle_loop_test.tres"
)
const DEFAULT_FRAMES := 600


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

	var metrics := BattleEnduranceMetrics.new()
	var runner := BattleEnduranceRunner.new()
	await runner.run(
		self,
		_resolve_frame_count(),
		metrics,
		scene.battle_services,
		120
	)
	# Active combat legitimately accumulates in-flight shells during this
	# short window. Post-battle cleanup profiles use the stricter defaults.
	# Thirty seconds can still contain long-range shells whose configured
	# lifetime exceeds the sample window. The pool/live-count invariant below
	# guards leaks while this budget permits those legitimate in-flight nodes.
	var failures := metrics.validate_bounded_growth(160, 48, 16)
	var summary := metrics.get_summary()
	print(
		"BATTLE_ENDURANCE_SMOKE frames=%d summary=%s failures=%d"
		% [_resolve_frame_count(), summary, failures.size()]
	)
	for failure in failures:
		push_error("BATTLE_ENDURANCE: %s" % failure)

	scene.shutdown()
	scene.queue_free()
	await process_frame
	await physics_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.call(&"clear_pool")
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _resolve_frame_count() -> int:
	var override := OS.get_environment("NAVYBLUE_ENDURANCE_FRAMES")
	return maxi(int(override), 1) \
		if override.is_valid_int() else DEFAULT_FRAMES
