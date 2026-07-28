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
	var non_carrier := battle.player_ship as ShipUnit
	_check(carrier != null and non_carrier != null, "battle ships exist")
	if carrier == null or non_carrier == null:
		await _finish(battle)
		return
	var snapshot := carrier.carrier_air_group_ai.get_debug_snapshot()
	_check(
		carrier.team == FactionRelations.ALLY \
			and not carrier.player_controlled,
		"ally carrier spawns as a non-player ship"
	)
	_check(
		carrier.carrier_air_group_ai.process_mode \
			!= Node.PROCESS_MODE_DISABLED \
			and carrier.carrier_air_group_ai.is_physics_processing() \
			and bool(snapshot.get("initialized", false)),
		"ally carrier AI is enabled after setup"
	)
	_check(
		non_carrier.carrier_air_group_ai.process_mode \
			== Node.PROCESS_MODE_DISABLED \
			and not non_carrier.carrier_air_group_ai \
				.is_physics_processing(),
		"non-carrier air group AI remains disabled"
	)
	carrier.player_controlled = true
	carrier._setup_carrier_components()
	_check(
		carrier.carrier_air_group_ai.process_mode \
			== Node.PROCESS_MODE_DISABLED \
			and not carrier.carrier_air_group_ai \
				.is_physics_processing(),
		"player-controlled carrier disables autonomous AI"
	)
	carrier.player_controlled = false
	carrier._setup_carrier_components()
	_check(
		carrier.carrier_air_group_ai.process_mode \
			!= Node.PROCESS_MODE_DISABLED \
			and carrier.carrier_air_group_ai \
				.is_physics_processing(),
		"returning command authority to AI re-enables processing"
	)
	carrier.health.current_health = 0.0
	carrier.health.died.emit()
	_check(
		carrier.carrier_air_group_ai.process_mode \
			== Node.PROCESS_MODE_DISABLED \
			and not carrier.carrier_air_group_ai \
				.is_physics_processing(),
		"carrier sinking shuts down its air group AI"
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
		push_error("CARRIER AI ACTIVATION TEST: %s" % failure)
	print(
		"CARRIER_AIR_GROUP_AI_ACTIVATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
