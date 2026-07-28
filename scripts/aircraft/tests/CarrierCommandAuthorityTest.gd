extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const CARRIER_AI_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_ai_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = CARRIER_AI_STAGE
	root.add_child(battle)
	await process_frame
	await physics_frame
	var carrier := _find_carrier(battle)
	var controller := battle.carrier_command_controller
	_check(
		carrier != null and controller != null,
		"authority test dependencies exist"
	)
	if carrier == null or controller == null:
		await _finish(battle)
		return
	controller.set_selected_carrier(carrier)
	_check(
		controller.get_selected_carrier() == null \
			and carrier.carrier_air_group_ai \
				.is_physics_processing(),
		"AI allied carrier cannot be selected by player commands"
	)
	carrier.player_controlled = true
	carrier._setup_carrier_components()
	controller.set_selected_carrier(carrier)
	_check(
		controller.get_selected_carrier() == carrier \
			and not carrier.carrier_air_group_ai \
				.is_physics_processing(),
		"player carrier gains command authority and disables AI"
	)
	carrier.player_controlled = false
	carrier._setup_carrier_components()
	controller.set_selected_carrier(carrier)
	_check(
		controller.get_selected_carrier() == null \
			and carrier.carrier_air_group_ai \
				.is_physics_processing(),
		"AI authority resumes without simultaneous player control"
	)
	await _finish(battle)


func _find_carrier(battle: BattleScene) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null \
				and ship.ship_id == "cv_seabastion" \
				and ship.team == FactionRelations.ALLY:
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER COMMAND AUTHORITY TEST: %s" % failure)
	print(
		"CARRIER_COMMAND_AUTHORITY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
