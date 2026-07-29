extends SceneTree

const TEST_LEVEL: StageData = preload(
	"res://resources/stages/test_level.tres"
)
const CARRIER_TEST: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var run_manager := root.get_node_or_null("RunManager")
	var spawn_system := SpawnSystem.new()
	root.add_child(spawn_system)
	await process_frame
	var config := NewRunConfig.new()
	config.starting_ship_id = "cv_seabastion"
	run_manager.start_new_run(config)
	_check(
		run_manager.get_selected_player_ship_id() == "cv_seabastion",
		"RunManager owns the selected ship id"
	)
	_check(
		spawn_system._resolve_player_ship_id(TEST_LEVEL) \
			== "cv_seabastion",
		"production stage resolves the run-selected ship"
	)
	config.starting_ship_id = "dd_bluewind"
	run_manager.start_new_run(config)
	_check(
		spawn_system._resolve_player_ship_id(CARRIER_TEST) \
			== "cv_seabastion",
		"explicit test stage override wins in tests"
	)
	run_manager.reset_run()
	spawn_system.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("PLAYER SHIP RESOLUTION TEST: %s" % failure)
	print(
		"PLAYER_SHIP_RESOLUTION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)
