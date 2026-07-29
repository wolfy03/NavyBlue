extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	var carrier := battle.player_ship as ShipUnit
	var controller := battle.aircraft_selection_controller
	battle.input_manager.set_command_mode(
		PlayerInputManager.CommandMode.AIRCRAFT
	)
	var fighter := carrier.carrier_air_group.launch_manual_squadron(
		"basic_fighter_squadron"
	)
	carrier.carrier_air_group.launch_cooldown_left = 0.0
	var bomber := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(fighter != null and bomber != null, "manual squadrons launch")
	if fighter != null and bomber != null:
		fighter.formation_center = Vector3(-80.0, 220.0, 0.0)
		bomber.formation_center = Vector3(80.0, 180.0, 0.0)
		var fighter_screen := battle.camera.unproject_position(
			fighter.formation_center
		)
		var bomber_screen := battle.camera.unproject_position(
			bomber.formation_center
		)
		var minimum := Vector2(
			minf(fighter_screen.x, bomber_screen.x),
			minf(fighter_screen.y, bomber_screen.y)
		) - Vector2(20.0, 20.0)
		var maximum := Vector2(
			maxf(fighter_screen.x, bomber_screen.x),
			maxf(fighter_screen.y, bomber_screen.y)
		) + Vector2(20.0, 20.0)
		controller.begin_drag(minimum)
		_check(
			controller.finish_drag(maximum),
			"drag gesture is consumed"
		)
		_check(
			controller.get_selected_squadrons().size() == 2,
			"drag selects multiple player squadrons"
		)
		_check(
			controller.issue_move_command(Vector3(700.0, 0.0, 400.0)),
			"right-click movement is issued to selected squadrons"
		)
		_check(
			fighter.is_player_commanded() \
				and bomber.is_player_commanded(),
			"movement keeps both roles under player authority"
		)
	controller.clear_selection()
	_check(not controller.has_selection(), "selection clears safely")
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("AIRCRAFT SELECTION CONTROLLER TEST: %s" % failure)
	print(
		"AIRCRAFT_SELECTION_CONTROLLER_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
