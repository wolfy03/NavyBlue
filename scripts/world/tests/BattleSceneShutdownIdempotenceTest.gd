extends SceneTree

const BATTLE_LOOP_STAGE: StageData = preload(
	"res://resources/stages/tests/battle_loop_test.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var packed := load(
		"res://scenes/world/battle_scene.tscn"
	) as PackedScene
	var scene := packed.instantiate() as BattleScene
	scene.stage_override = BATTLE_LOOP_STAGE
	root.add_child(scene)
	await process_frame
	await physics_frame
	_check(scene.initialization_result.success, "battle initializes")
	var services := scene.battle_services
	scene.shutdown()
	scene.shutdown()
	await process_frame
	_check(
		scene.is_shutdown_completed()
			and not services.is_configured()
			and scene.input_manager != null
			and not scene.input_manager.is_input_enabled(),
		"shutdown is ordered and idempotent"
	)
	scene.queue_free()
	await process_frame
	await process_frame
	print("BATTLE_SCENE_SHUTDOWN_IDEMPOTENCE_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("BATTLE SCENE SHUTDOWN: %s" % label)
