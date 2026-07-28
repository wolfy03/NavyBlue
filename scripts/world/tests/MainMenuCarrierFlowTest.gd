extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const MAIN_MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/test_level.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var menu := MAIN_MENU_SCENE.instantiate() as Control
	root.add_child(menu)
	var selector := menu.get_node(
		"Root/Panel/VBox/Tabs/NewGame/NewGameContent/StartingShip/StartingShipSelector"
	) as OptionButton
	var carrier_index := -1
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == "cv_seabastion":
			carrier_index = index
			break
	_check(
		carrier_index >= 0,
		"main menu offers Seabastion as a starting ship"
	)
	if carrier_index >= 0:
		selector.select(carrier_index)
		_check(
			str(menu.call(&"_get_selected_ship_id")) \
				== "cv_seabastion",
			"main menu resolves the selected carrier id"
		)
	menu.queue_free()
	await process_frame
	var run_manager := root.get_node_or_null("RunManager")
	run_manager.start_new_run({
		"sea_id": STAGE.sea_id,
		"stage_id": STAGE.id,
		"player_ship_state": {
			"ship_id": "cv_seabastion",
		},
	})
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	var carrier := battle.player_ship as ShipUnit
	_check(
		carrier != null \
			and carrier.ship_id == "cv_seabastion" \
			and carrier.player_controlled,
		"run-selected carrier overrides the generic stage player ship"
	)
	if carrier != null:
		var states := carrier.carrier_air_group \
			.get_all_squadron_states()
		var ids: Array[String] = []
		for state in states:
			ids.append(state.squadron_id)
		_check(
			ids.has("basic_bomber_squadron") \
				and ids.has("basic_fighter_squadron"),
			"player carrier initializes bomber and fighter squadrons"
		)
		var fighter := carrier.carrier_air_group \
			.launch_manual_squadron("basic_fighter_squadron")
		_check(
			fighter != null and fighter.is_player_commanded(),
			"player carrier can manually launch its fighter squadron"
		)
		if fighter != null:
			battle.aircraft_selection_controller.select_squadron(
				fighter
			)
			_check(
				battle.aircraft_selection_controller.has_selection(),
				"manually launched player fighter is selectable"
			)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("MAIN MENU CARRIER FLOW TEST: %s" % failure)
	print(
		"MAIN_MENU_CARRIER_FLOW_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
