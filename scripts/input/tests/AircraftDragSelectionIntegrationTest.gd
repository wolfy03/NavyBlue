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
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_fighter_squadron"
	)
	_check(squadron != null, "manual fighter launches")
	if squadron != null:
		squadron.set_physics_process(false)
		squadron.formation_center = Vector3(0.0, 220.0, 0.0)
		var aircraft := squadron.aircraft_units[0]
		aircraft.activate()
		aircraft.global_position = squadron.formation_center \
			+ Vector3(90.0, 0.0, 0.0)
		var screen := battle.camera.unproject_position(
			aircraft.global_position
		)
		var controller := battle.aircraft_selection_controller
		controller.begin_drag(screen - Vector2(10.0, 10.0))
		_check(
			controller.finish_drag(screen + Vector2(10.0, 10.0)),
			"drag around an individual aircraft is consumed"
		)
		_check(
			controller.get_selected_squadrons().has(squadron),
			"individual-aircraft drag selects the owning squadron"
		)
		controller.clear_selection()
		controller.begin_drag(screen)
		_check(
			controller.finish_drag(screen + Vector2(2.0, 2.0)),
			"short drag performs click selection"
		)
		_check(controller.has_selection(), "click selection selects squadron")
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("AIRCRAFT DRAG SELECTION TEST: %s" % failure)
	print(
		"AIRCRAFT_DRAG_SELECTION_INTEGRATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
