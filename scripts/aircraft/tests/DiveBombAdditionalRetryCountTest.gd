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
	var squadron := _launch_squadron(battle)
	if squadron == null:
		await _finish(battle)
		return
	var aircraft := squadron.get_alive_aircraft()
	for index in range(1, aircraft.size()):
		aircraft[index].weapon_controller.remaining_ammunition = 0
		aircraft[index].global_position.y = 120.0
	var attacker := aircraft[0]
	attacker.global_position = Vector3(0.0, 95.0, 200.0)
	attacker.weapon_controller.release_cooldown_left = 10.0
	var controller := squadron.dive_bomb_controller
	controller.maximum_additional_release_retries = 0
	controller.release_retry_interval_sec = 0.0
	_start_ready_dive(controller)
	controller.update_dive(0.0)
	_check(
		controller.get_aircraft_release_state(attacker) \
			== DiveBombAttackController.AircraftReleaseState.FAILED,
		"zero additional retries fails after the initial request"
	)
	_check(
		int(controller._aircraft_release_attempts.get(
			attacker.get_instance_id(),
			-1
		)) == 0,
		"zero additional retries records no retry"
	)
	controller.cancel()

	attacker.weapon_controller.release_cooldown_left = 10.0
	controller.maximum_additional_release_retries = 3
	_start_ready_dive(controller)
	for _index in 4:
		controller.update_dive(0.0)
	_check(
		controller.get_aircraft_release_state(attacker) \
			== DiveBombAttackController.AircraftReleaseState.FAILED,
		"three additional retries eventually exhaust"
	)
	_check(
		int(controller._aircraft_release_attempts.get(
			attacker.get_instance_id(),
			-1
		)) == 3,
		"initial request permits exactly three additional retries"
	)
	await _finish(battle)


func _start_ready_dive(controller: DiveBombAttackController) -> void:
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"retry-count dive starts"
	)
	controller.dive_elapsed_seconds = 1.0
	controller.update_dive(0.0)


func _launch_squadron(battle: BattleScene) -> AircraftSquadron:
	var carrier := battle.player_ship as ShipUnit
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null, "manual bomber squadron launches")
	if squadron == null:
		return null
	squadron.set_physics_process(false)
	squadron.formation_center = Vector3(0.0, 180.0, 200.0)
	squadron._formation_forward = Vector3(0.0, 0.0, -1.0)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	return squadron


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB ADDITIONAL RETRY COUNT TEST: %s" % failure)
	print(
		"DIVE_BOMB_ADDITIONAL_RETRY_COUNT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
