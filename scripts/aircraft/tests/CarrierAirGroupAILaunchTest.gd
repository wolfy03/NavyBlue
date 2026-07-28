extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const CARRIER_AI_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_ai_test.tres"
)
const SQUADRON_ID := "basic_bomber_squadron"

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
	_check(carrier != null, "battle provides an allied AI carrier")
	if carrier == null:
		await _finish(battle)
		return
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null:
			ship.set_physics_process(false)
	var ai := carrier.carrier_air_group_ai
	var group := carrier.carrier_air_group
	ai.shutdown()
	group.setup(carrier, carrier.ship_data.carrier_air_group_data)
	group.process_mode = Node.PROCESS_MODE_INHERIT
	ai.process_mode = Node.PROCESS_MODE_INHERIT
	ai.setup(carrier, group)
	var launchable := group.get_launchable_squadron_ids()
	_check(
		launchable == [SQUADRON_ID],
		"AI resolves the concrete launchable squadron id"
	)
	_check(
		group.get_default_strike_mission(SQUADRON_ID) != null,
		"default strike mission is data-driven and available"
	)
	var target := ai.select_strike_target()
	_check(
		target != null and carrier.is_hostile_to(target),
		"AI selects a hostile ship and excludes friendlies"
	)
	var enemy_positions: Dictionary = {}
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null and carrier.is_hostile_to(ship):
			enemy_positions[ship.get_instance_id()] = ship.global_position
			ship.global_position = carrier.global_position \
				+ Vector3(0.0, 0.0, 9000.0)
	_check(
		ai.select_strike_target() == null,
		"targets beyond the 8 km combat radius are excluded"
	)
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null and enemy_positions.has(ship.get_instance_id()):
			ship.global_position = enemy_positions[ship.get_instance_id()]
	ai.update_ai(10.0)
	_check(
		group.get_active_squadron_count() == 1,
		"AI decision launches a strike squadron"
	)
	var snapshot := ai.get_debug_snapshot()
	_check(
		int(snapshot.get("decision_count", 0)) == 1 \
			and str(snapshot.get("selected_target", "")) != "" \
			and str(snapshot.get(
				"last_launch_block_reason",
				""
			)) == "NONE",
		"successful decision records target and no block reason"
	)
	ai.update_ai(10.0)
	_check(
		group.get_active_squadron_count() == 1 \
			and ai.get_last_launch_block_reason() \
				== CarrierAirGroupAI.LaunchBlockReason.LAUNCH_COOLDOWN,
		"launch cooldown blocks an immediate second sortie"
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
		push_error("CARRIER AI LAUNCH TEST: %s" % failure)
	print(
		"CARRIER_AIR_GROUP_AI_LAUNCH_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
