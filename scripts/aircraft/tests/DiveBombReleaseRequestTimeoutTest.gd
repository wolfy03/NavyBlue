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
	var release_settings := squadron.payload_release_settings.duplicate(
		true
	) as AircraftPayloadReleaseSettings
	release_settings.request_timeout_sec = 0.01
	squadron.set_payload_release_settings(release_settings)
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
	aircraft.weapon_controller.release_cooldown_left = 10.0
	squadron.payload_release_coordinator.update(0.02)
	_check(
		squadron.get_release_debug_snapshot().active_request_ids.is_empty(),
		"timed-out request is removed"
	)
	_check(
		not aircraft.weapon_controller.is_release_in_progress(),
		"timed-out WeaponController request is cancelled"
	)
	var result := squadron.payload_release_coordinator \
		.get_last_aircraft_result(
			aircraft.get_instance_id()
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
