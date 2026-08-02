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
	var controller := squadron.dive_bomb_controller
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.NONE
		) == DiveBombAttackController.BeginDiveResult.INVALID_CONFIGURATION,
		"NONE control source is rejected"
	)
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"PLAYER control source starts a dive"
	)
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult \
			.ALREADY_ACTIVE_SAME_SOURCE,
		"same active source is idempotent"
	)
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.AI
		) == DiveBombAttackController.BeginDiveResult.CONTROL_CONFLICT,
		"different active source is rejected"
	)
	controller.cancel()

	var aircraft := squadron.get_alive_aircraft()[0]
	var release_context := AircraftPayloadReleaseContext.create(
		Vector3.ZERO,
		Vector3.ZERO
	)
	var request_result := squadron.request_aircraft_payload_release(
		aircraft,
		release_context
	)
	_check(
		request_result.status \
			== AircraftPayloadReleaseRequestResult.Status.QUEUED,
		"previous payload request is queued"
	)
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.AI
		) == DiveBombAttackController.BeginDiveResult.RELEASE_CONFLICT,
		"active payload request blocks a new dive"
	)
	squadron.cancel_pending_weapon_release()
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.AI
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"new dive can start after pending request cancellation"
	)
	_check(
		not controller.is_solution_locked(),
		"AI solution remains open during DIVE_ENTRY"
	)
	controller.update_target(
		Vector3(120.0, 0.0, 80.0),
		Vector3(10.0, 0.0, 0.0)
	)
	_check(
		controller.target_position.is_equal_approx(
			Vector3(120.0, 0.0, 80.0)
		),
		"AI can refresh the target before the dive transition"
	)
	controller.update_dive(0.0)
	_check(
		not controller.is_solution_locked() \
			and controller.state == DiveBombAttackController.State.DIVE_ENTRY,
		"AI waits in DIVE_ENTRY for the mission's final refresh"
	)
	controller.lock_solution()
	controller.update_dive(0.0)
	_check(
		controller.is_solution_locked() \
			and controller.state == DiveBombAttackController.State.DIVING,
		"AI commits to DIVING only after the final solution lock"
	)
	controller.cancel()
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB NO SOURCE BEGIN TEST: %s" % failure)
	print(
		"DIVE_BOMB_NO_SOURCE_BEGIN_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
