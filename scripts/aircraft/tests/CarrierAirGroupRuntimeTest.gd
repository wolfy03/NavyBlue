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
	var carrier := _find_carrier(battle)
	_check(carrier != null, "battle provides a carrier")
	if carrier == null:
		await _finish(battle)
		return
	carrier.carrier_air_group_ai.shutdown()
	carrier.carrier_air_group_ai.process_mode = \
		Node.PROCESS_MODE_DISABLED
	await process_frame
	await physics_frame
	for ship in battle.get_battle_units():
		(ship as ShipUnit).set_physics_process(false)
	var group := carrier.carrier_air_group
	group.restore_from_save_data({
		"squadrons": {
			SQUADRON_ID: {
				"squadron_id": SQUADRON_ID,
				"availability_state":
					SquadronRuntimeState.AvailabilityState.READY,
				"total_aircraft": 4,
				"available_aircraft": 2,
				"active_aircraft": 0,
				"lost_aircraft": 2,
				"rearm_time_left": 0.0,
			},
		},
	})
	group.launch_cooldown_left = 0.0
	var squadron := group.launch_squadron(
		SQUADRON_ID,
		carrier.global_position + Vector3(0.0, 80.0, -250.0)
	)
	_check(squadron != null, "a partial squadron launches")
	if squadron != null:
		_check(
			squadron.aircraft_units.size() == 2,
			"available aircraft count controls sortie size"
		)
		var victim := squadron.aircraft_units[0]
		victim.apply_damage(10000.0)
		await process_frame
		await process_frame
		var damaged_state := group.get_squadron_state(SQUADRON_ID)
		_check(
			damaged_state.active_aircraft == 1 \
				and damaged_state.lost_aircraft == 3,
			"aircraft destruction updates active and lost counts once"
		)
		group.call(&"_on_squadron_recovered", squadron)
		var recovered_state := group.get_squadron_state(SQUADRON_ID)
		_check(
			recovered_state.available_aircraft == 1 \
				and recovered_state.availability_state \
					== SquadronRuntimeState.AvailabilityState.REARMING,
			"survivors enter rearming after recovery"
		)
		group.call(&"_process", 30.0)
		var ready_state := group.get_squadron_state(SQUADRON_ID)
		_check(
			ready_state.availability_state \
				== SquadronRuntimeState.AvailabilityState.READY,
			"rearming completes into READY"
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
		push_error("CARRIER AIR GROUP RUNTIME TEST: %s" % failure)
	print(
		"CARRIER_AIR_GROUP_RUNTIME_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
