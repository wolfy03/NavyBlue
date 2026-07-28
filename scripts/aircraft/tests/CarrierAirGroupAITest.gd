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
	_check(carrier != null, "battle provides an AI carrier")
	if carrier == null:
		await _finish(battle)
		return
	carrier.carrier_air_group_ai.setup(
		carrier,
		carrier.carrier_air_group
	)
	var initial_snapshot := carrier.carrier_air_group_ai.get_debug_snapshot()
	_check(
		bool(initial_snapshot.get("initialized", false)) \
			and carrier.carrier_air_group_ai.is_physics_processing(),
		"ally AI carrier is initialized and physics processing"
	)
	var target := carrier.carrier_air_group_ai.select_strike_target()
	_check(
		target != null and carrier.is_hostile_to(target),
		"ally carrier AI selects a live hostile target in combat radius"
	)
	carrier.health.current_health = carrier.health.max_health * 0.35
	_check(
		carrier.carrier_air_group_ai.should_stop_launching(),
		"AI stops launching below its health threshold"
	)
	carrier.health.current_health = carrier.health.max_health * 0.2
	_check(
		carrier.carrier_air_group_ai.should_recall_all(),
		"AI recalls squadrons at critical health"
	)
	var snapshot := carrier.carrier_air_group_ai.get_debug_snapshot()
	_check(
		snapshot.has("candidate_count") \
			and snapshot.has("target_score"),
		"AI exposes a bounded debug snapshot"
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
		push_error("CARRIER AIR GROUP AI TEST: %s" % failure)
	print(
		"CARRIER_AIR_GROUP_AI_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
