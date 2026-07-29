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
	var controller := squadron.dive_bomb_controller
	controller.target_position = Vector3.ZERO
	controller.dive_elapsed_seconds = 1.0
	controller.state = DiveBombAttackController.State.DIVING
	var aircraft := squadron.get_alive_aircraft()
	for index in aircraft.size():
		aircraft[index].global_position = Vector3(
			float(index) * 90.0,
			100.0 if index < 2 else 200.0,
			0.0
		)
	_check(
		squadron.get_release_ready_aircraft_count(0.0, 70.0, 160.0)
			== 2,
		"real aircraft altitude identifies the first release subset"
	)
	_check(
		controller.release_ready_bombs() == 2,
		"only the first release-ready subset is queued"
	)
	_check(
		controller.state == DiveBombAttackController.State.BOMB_RELEASED,
		"partial release keeps the squadron in its dive"
	)
	_drain_release_queue(squadron)
	for index in range(2, aircraft.size()):
		aircraft[index].global_position.y = 100.0
	_check(
		controller.release_ready_bombs() == aircraft.size() - 2,
		"remaining aircraft can release later in the same dive"
	)
	_drain_release_queue(squadron)
	controller.update_dive(0.01)
	_check(
		controller.state == DiveBombAttackController.State.PULLING_OUT,
		"ammunition depletion starts pull-out after all subsets release"
	)
	await _finish(battle)


func _drain_release_queue(squadron: AircraftSquadron) -> void:
	for _index in 16:
		squadron._update_weapon_release_sequence(1.0)
		if not squadron.is_weapon_release_in_progress():
			return


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB PARTIAL RELEASE TEST: %s" % failure)
	print(
		"DIVE_BOMB_PARTIAL_SQUADRON_RELEASE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
