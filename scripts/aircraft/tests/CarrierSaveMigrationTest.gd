extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const CARRIER_PLAYER_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const SQUADRON_ID := "basic_bomber_squadron"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var run_manager := root.get_node_or_null("RunManager")
	_check(run_manager != null, "RunManager exists")
	if run_manager != null:
		run_manager.restore_from_save_data({
			"version": 1,
			"is_run_active": true,
			"player_ship_state": {"ship_id": "cv_seabastion"},
		})
		_check(
			run_manager.carrier_air_group_states.is_empty(),
			"version 1 save migrates without carrier state"
		)
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = CARRIER_PLAYER_STAGE
	root.add_child(battle)
	await process_frame
	await physics_frame
	var carrier := battle.player_ship as ShipUnit
	_check(carrier != null, "player carrier exists")
	if carrier != null:
		var group := carrier.carrier_air_group
		var initial := group.get_squadron_state(SQUADRON_ID)
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
				"removed_squadron": {
					"squadron_id": "removed_squadron",
					"total_aircraft": 9,
				},
			},
		})
		var restored := group.get_squadron_state(SQUADRON_ID)
		_check(
			restored != null \
				and restored.active_aircraft == 0 \
				and restored.available_aircraft == 3 \
				and restored.lost_aircraft == 1,
			"active saved aircraft return to READY on migration"
		)
		_check(
			group.get_squadron_state("removed_squadron") == null,
			"unknown saved squadron is ignored"
		)
		var fighter_state := group.get_squadron_state(
			"basic_fighter_squadron"
		)
		_check(
			fighter_state != null \
				and fighter_state.availability_state \
				== SquadronRuntimeState.AvailabilityState.READY \
				and fighter_state.available_aircraft \
				== fighter_state.total_aircraft,
			"resource-defined fighter remains READY after bomber-only save"
		)
		var before_mismatch := group.to_save_data()
		if run_manager != null:
			run_manager.carrier_air_group_states[
				RunManager.PLAYER_CARRIER_KEY
			] = {
				"ship_id": "dd_bluewind",
				"air_group_id": group.air_group_data.id,
				"squadrons": {},
			}
			run_manager.restore_carrier_air_group(carrier)
		_check(
			group.to_save_data() == before_mismatch,
			"mismatched carrier save is rejected"
		)
		_check(initial != null, "resource-defined squadron remains available")
		_check(
			not JSON.stringify(group.to_save_data()).is_empty(),
			"carrier save data remains JSON-safe"
		)
	battle.queue_free()
	await process_frame
	if run_manager != null:
		run_manager.reset_run()
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("CARRIER SAVE MIGRATION TEST: %s" % failure)
	print(
		"CARRIER_SAVE_MIGRATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)
