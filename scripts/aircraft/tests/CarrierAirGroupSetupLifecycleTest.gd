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
	_check(carrier != null, "AI carrier exists")
	if carrier != null:
		var ai := carrier.carrier_air_group_ai
		_check(_is_ai_active(ai), "initial setup enables AI processing")
		ai.shutdown()
		_check(
			not ai.is_physics_processing(),
			"shutdown disables AI processing"
		)
		ai.setup(carrier, carrier.carrier_air_group)
		_check(_is_ai_active(ai), "setup after shutdown is safe")
		ai.setup(carrier, carrier.carrier_air_group)
		_check(_is_ai_active(ai), "repeated setup remains safe")
	battle.queue_free()
	await process_frame
	_finish()


func _is_ai_active(ai: CarrierAirGroupAI) -> bool:
	if ai == null:
		return false
	var snapshot := ai.get_debug_snapshot()
	return bool(snapshot.get("initialized", false)) \
		and ai.process_mode != Node.PROCESS_MODE_DISABLED \
		and ai.is_physics_processing()


func _find_carrier(battle: BattleScene) -> ShipUnit:
	for value in battle.allies:
		var ship := value as ShipUnit
		if ship != null and ship.ship_id == "cv_seabastion":
			return ship
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("CARRIER AIR GROUP SETUP LIFECYCLE TEST: %s" % failure)
	print(
		"CARRIER_AIR_GROUP_SETUP_LIFECYCLE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)
