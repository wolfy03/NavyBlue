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
	squadron.aircraft_release_request_timeout_sec = 0.01
	_check(
		squadron.request_aircraft_weapon_release(
			aircraft,
			Vector3.ZERO,
			Vector3.ZERO
		) == AircraftSquadron.AircraftReleaseRequestResult.QUEUED,
		"payload request is queued"
	)
	for request_id in squadron._active_aircraft_release_requests.keys():
		var data: Dictionary = \
			squadron._active_aircraft_release_requests[request_id]
		data["requested_at"] = Time.get_ticks_msec() - 1000
	squadron._update_release_request_timeouts()
	_check(
		squadron.get_release_debug_snapshot().active_request_ids.is_empty(),
		"timed-out request is removed"
	)
	_check(
		not aircraft.weapon_controller.is_release_in_progress(),
		"timed-out WeaponController request is cancelled"
	)
	var result: Dictionary = squadron._last_aircraft_release_results.get(
		aircraft.get_instance_id(),
		{}
	)
	_check(
		bool(result.get("cancelled", false)),
		"timeout records a cancelled result"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB REQUEST TIMEOUT TEST: %s" % failure)
	print(
		"DIVE_BOMB_RELEASE_REQUEST_TIMEOUT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
