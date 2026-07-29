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
	var controller := battle.aircraft_selection_controller
	_check(
		controller.get_selection_block_reason(squadron) \
			== AircraftSelectionController.SelectionBlockReason.NONE,
		"player HOLDING/EN_ROUTE squadron is selectable"
	)
	carrier.player_controlled = false
	_check(
		controller.get_selection_block_reason(squadron) \
			== AircraftSelectionController.SelectionBlockReason \
				.CARRIER_NOT_PLAYER_CONTROLLED,
		"AI-owned carrier blocks selection"
	)
	carrier.player_controlled = true
	squadron.state = AircraftSquadron.State.RETURNING
	_check(
		controller.get_selection_block_reason(squadron) \
			== AircraftSelectionController.SelectionBlockReason.RETURNING,
		"returning squadron blocks selection"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("AIRCRAFT SELECTION REASON TEST: %s" % failure)
	print(
		"AIRCRAFT_SELECTION_CANDIDATE_REASON_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
