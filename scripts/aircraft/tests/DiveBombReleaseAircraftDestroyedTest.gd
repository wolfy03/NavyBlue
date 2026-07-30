extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []
var _pass_completed_count := 0


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
	var victim := aircraft[0]
	var victim_id := victim.get_instance_id()
	victim.global_position = Vector3(0.0, 95.0, 200.0)
	var controller := squadron.dive_bomb_controller
	controller.automatic_release_pass_completed.connect(
		func(
			_released: int,
			_failed: int,
			_skipped: int,
			_cancelled: bool
		) -> void:
			_pass_completed_count += 1
	)
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"destroyed-aircraft dive starts"
	)
	controller.dive_elapsed_seconds = 1.0
	controller.update_dive(0.0)
	controller.update_dive(0.0)
	_check(
		controller.get_aircraft_release_state(victim) \
			== DiveBombAttackController.AircraftReleaseState.REQUESTED,
		"aircraft has an active payload request before destruction"
	)
	victim.destroy_for_cleanup()
	_check(
		int(controller._aircraft_release_states.get(
			victim_id,
			-1
		)) == DiveBombAttackController.AircraftReleaseState.FAILED,
		"destroyed aircraft request resolves to FAILED by aircraft id"
	)
	_check(
		squadron.get_release_debug_snapshot().active_request_ids.is_empty(),
		"destroyed aircraft active request is removed immediately"
	)
	controller.update_dive(0.0)
	_check(
		controller.state == DiveBombAttackController.State.PULLING_OUT,
		"controller leaves RELEASING after aircraft destruction"
	)
	_check(
		_pass_completed_count == 1,
		"release pass completion is emitted once"
	)
	await _finish(battle)


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
		push_error("DIVE BOMB AIRCRAFT DESTROYED TEST: %s" % failure)
	print(
		"DIVE_BOMB_RELEASE_AIRCRAFT_DESTROYED_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
