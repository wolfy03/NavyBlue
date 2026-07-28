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
	_check(carrier != null, "carrier exists")
	if carrier != null:
		carrier.carrier_air_group_ai.shutdown()
		carrier.carrier_air_group_ai.process_mode = \
			Node.PROCESS_MODE_DISABLED
		await process_frame
		await physics_frame
		var group := carrier.carrier_air_group
		group.restore_from_save_data({
			"air_group_id": group.air_group_data.id,
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
		})
		group.resolve_carrier_loss()
		var first := group.to_save_data()
		group.resolve_carrier_loss()
		group.resolve_battle_end(false)
		var repeated := group.to_save_data()
		_check(
			first == repeated,
			"carrier loss and battle failure settlement are idempotent"
		)
		var state := group.get_squadron_state(SQUADRON_ID)
		_check(
			state != null \
				and state.active_aircraft == 0 \
				and state.lost_aircraft == state.total_aircraft,
			"loss counters do not double-decrement"
		)
	battle.queue_free()
	await process_frame
	_finish()


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
		push_error("CARRIER BATTLE END IDEMPOTENCY TEST: %s" % failure)
	print(
		"CARRIER_BATTLE_END_IDEMPOTENCY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)
