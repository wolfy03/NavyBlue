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
	var group := carrier.carrier_air_group
	group.restore_from_save_data(_make_active_state())
	group.resolve_battle_end(true)
	var victory := group.get_squadron_state(SQUADRON_ID)
	_check(
		victory.available_aircraft == 3 \
			and victory.active_aircraft == 0 \
			and victory.lost_aircraft == 1 \
			and victory.availability_state \
				== SquadronRuntimeState.AvailabilityState.READY,
		"victory returns airborne survivors and preserves losses"
	)
	group.setup(carrier, carrier.ship_data.carrier_air_group_data)
	group.restore_from_save_data(_make_active_state())
	group.resolve_battle_end(false)
	var loss := group.get_squadron_state(SQUADRON_ID)
	_check(
		loss.active_aircraft == 0 \
			and loss.available_aircraft == 0 \
			and loss.lost_aircraft == loss.total_aircraft \
			and loss.availability_state \
				== SquadronRuntimeState.AvailabilityState.DESTROYED,
		"carrier loss marks all aircraft destroyed"
	)
	await _finish(battle)


func _make_active_state() -> Dictionary:
	return {
		"squadrons": {
			SQUADRON_ID: {
				"squadron_id": SQUADRON_ID,
				"availability_state":
					SquadronRuntimeState.AvailabilityState.ACTIVE,
				"total_aircraft": 4,
				"available_aircraft": 1,
				"active_aircraft": 2,
				"lost_aircraft": 1,
				"rearm_time_left": 0.0,
			},
		},
	}


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
		push_error("CARRIER BATTLE END TEST: %s" % failure)
	print(
		"CARRIER_BATTLE_END_RESOLUTION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
