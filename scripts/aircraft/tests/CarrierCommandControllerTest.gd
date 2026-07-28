extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const CARRIER_PLAYER_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = CARRIER_PLAYER_STAGE
	root.add_child(battle)
	await process_frame
	await physics_frame
	var controller := battle.carrier_command_controller
	var panel := battle.carrier_air_group_panel
	var carrier := _find_ship(battle, "cv_seabastion")
	var non_carrier := _find_non_carrier(battle)
	var enemy := _find_enemy(battle)
	_check(
		controller != null and panel != null,
		"carrier command UI is present"
	)
	controller.set_selected_carrier(non_carrier)
	_check(not panel.visible, "panel hides for a non-carrier")
	controller.set_selected_carrier(carrier)
	_check(panel.visible, "panel shows for a selected carrier")
	_check(
		carrier.player_controlled \
			and not bool(carrier.carrier_air_group_ai.get_debug_snapshot().get(
			"initialized",
			false
		)),
		"player-controlled carrier AI is disabled"
	)
	var launchable := carrier.carrier_air_group.get_launchable_squadron_ids()
	_check(not launchable.is_empty(), "selected carrier has a launchable squadron")
	if not launchable.is_empty():
		_check(
			controller.begin_strike_targeting(launchable[0]),
			"strike targeting mode starts"
		)
		_check(controller.is_targeting(), "targeting state is exposed")
		_check(
			not controller.try_issue_strike(non_carrier),
			"friendly targets are rejected"
		)
		_check(
			controller.try_issue_strike(enemy),
			"enemy click issues a strike through CarrierAirGroup"
		)
		_check(
			not controller.is_targeting(),
			"successful strike exits targeting mode"
		)
	await _finish(battle)


func _find_ship(battle: BattleScene, ship_id: String) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null \
				and ship.ship_id == ship_id \
				and (
					ship_id != "cv_seabastion" \
					or ship.team == FactionRelations.PLAYER
				):
			return ship
	return null


func _find_enemy(battle: BattleScene) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null and ship.team == FactionRelations.ENEMY:
			return ship
	return null


func _find_non_carrier(battle: BattleScene) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null \
				and (
					ship.ship_data == null \
					or ship.ship_data.carrier_air_group_data == null
				):
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER COMMAND CONTROLLER TEST: %s" % failure)
	print(
		"CARRIER_COMMAND_CONTROLLER_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
