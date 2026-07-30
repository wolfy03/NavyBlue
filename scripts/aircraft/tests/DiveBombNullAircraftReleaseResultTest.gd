extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	var carrier := battle.player_ship as ShipUnit
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null, "manual bomber squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	var aircraft := squadron.get_alive_aircraft()[0]
	var aircraft_id := aircraft.get_instance_id()
	squadron.begin_dive_release_pass()
	var request_result := squadron.request_aircraft_payload_release(
		aircraft,
		AircraftPayloadReleaseContext.create(
			Vector3.ZERO,
			Vector3.ZERO
		)
	)
	_check(
		request_result.status \
			== AircraftPayloadReleaseRequestResult.Status.QUEUED,
		"payload request is queued"
	)
	var request_ids: Array = squadron \
		.get_release_debug_snapshot().active_request_ids
	_check(request_ids.size() == 1, "one request is active")
	aircraft.queue_free()
	await process_frame
	squadron.payload_release_coordinator.cancel_aircraft_requests(
		aircraft_id
	)
	var result := squadron.payload_release_coordinator \
		.get_last_aircraft_result(
			aircraft_id
	)
	_check(
		not result.is_empty() and bool(result.get("cancelled", false)),
		"null aircraft result is recorded by stored aircraft id"
	)
	_check(
		squadron.get_release_debug_snapshot().active_request_ids.is_empty(),
		"null aircraft result removes the active request"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB NULL AIRCRAFT RESULT TEST: %s" % failure)
	print(
		"DIVE_BOMB_NULL_AIRCRAFT_RELEASE_RESULT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
