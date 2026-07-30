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
		"basic_bomber_squadron"
	)
	_check(squadron != null, "manual bomber squadron launches")
	if squadron == null:
		await _finish(battle)
		return

	squadron.set_physics_process(false)
	squadron.formation_center = Vector3(0.0, 120.0, 200.0)
	squadron._formation_forward = Vector3(0.0, 0.0, -1.0)
	var aircraft := squadron.aircraft_units
	for index in aircraft.size():
		aircraft[index].activate()
		aircraft[index].set_physics_process(false)
		aircraft[index].global_position = Vector3(
			float(index) * 20.0,
			120.0,
			200.0
		)

	var controller := squadron.dive_bomb_controller
	controller.dive_data.pull_out_aircraft_ratio = 0.5
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"ratio test dive starts"
	)
	controller.update_dive(0.0)
	aircraft[0].global_position.y = 40.0
	controller.update_dive(0.0)
	_check(
		controller.state == DiveBombAttackController.State.DIVING,
		"one low aircraft does not pull out a four-aircraft squadron"
	)

	aircraft[1].global_position.y = 40.0
	controller.update_dive(0.0)
	_check(
		controller.state == DiveBombAttackController.State.PULLING_OUT,
		"configured aircraft ratio starts group pull-out"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB PULL-OUT RATIO TEST: %s" % failure)
	print(
		"DIVE_BOMB_PULL_OUT_RATIO_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
