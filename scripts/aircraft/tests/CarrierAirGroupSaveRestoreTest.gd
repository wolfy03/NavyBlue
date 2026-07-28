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
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = CARRIER_PLAYER_STAGE
	root.add_child(battle)
	await process_frame
	await physics_frame
	var carrier := _find_carrier(battle)
	var run_manager := root.get_node_or_null("RunManager")
	_check(carrier != null and run_manager != null, "save test dependencies exist")
	if carrier == null or run_manager == null:
		await _finish(battle)
		return
	carrier.carrier_air_group.restore_from_save_data({
		"squadrons": {
			SQUADRON_ID: {
				"squadron_id": SQUADRON_ID,
				"availability_state":
					SquadronRuntimeState.AvailabilityState.READY,
				"total_aircraft": 4,
				"available_aircraft": 3,
				"active_aircraft": 0,
				"lost_aircraft": 1,
				"rearm_time_left": 0.0,
			},
		},
	})
	run_manager.capture_carrier_air_group(carrier)
	var saved: Dictionary = \
		run_manager.carrier_air_group_states.duplicate(true)
	_check(
		_is_json_safe(saved),
		"carrier save data contains no Node, Resource, Callable, or WeakRef"
	)
	carrier.carrier_air_group.setup(
		carrier,
		carrier.ship_data.carrier_air_group_data
	)
	run_manager.restore_carrier_air_group(carrier)
	var restored := carrier.carrier_air_group.get_squadron_state(
		SQUADRON_ID
	)
	_check(
		restored.available_aircraft == 3 \
			and restored.lost_aircraft == 1,
		"remaining aircraft restore from RunManager"
	)
	run_manager.restore_from_save_data({
		"version": 1,
		"is_run_active": true,
	})
	_check(
		run_manager.carrier_air_group_states.is_empty(),
		"version 1 saves restore without carrier state"
	)
	await _finish(battle)


func _is_json_safe(value: Variant) -> bool:
	if value is Node or value is Resource \
			or value is Callable or value is WeakRef:
		return false
	if value is Array:
		for item in value:
			if not _is_json_safe(item):
				return false
	elif value is Dictionary:
		for key in value:
			if not _is_json_safe(key) \
					or not _is_json_safe(value[key]):
				return false
	return true


func _find_carrier(battle: BattleScene) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null \
				and ship.ship_id == "cv_seabastion" \
				and ship.team == FactionRelations.PLAYER:
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER AIR GROUP SAVE TEST: %s" % failure)
	print(
		"CARRIER_AIR_GROUP_SAVE_RESTORE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
