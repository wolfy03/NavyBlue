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
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
	var controller := squadron.dive_bomb_controller
	controller.target_position = Vector3.ZERO
	controller.dive_elapsed_seconds = 1.0
	controller.state = DiveBombAttackController.State.DIVING
	squadron.formation_center = Vector3(0.0, 100.0, 0.0)
	for aircraft in squadron.get_alive_aircraft():
		aircraft.global_position = Vector3(0.0, 200.0, 0.0)
	_check(
		not controller.can_release_bombs() \
			and controller.release_block_reason \
			== DiveBombAttackController.ReleaseBlockReason \
				.NO_AIRCRAFT_IN_RELEASE_ALTITUDE,
		"release is blocked when no aircraft is inside its altitude window"
	)
	var alive := squadron.get_alive_aircraft()
	alive[0].global_position = Vector3(100.0, 100.0, 0.0)
	for index in range(1, alive.size()):
		alive[index].global_position = Vector3(
			float(index) * 100.0,
			200.0,
			0.0
		)
	_check(
		controller.can_release_bombs(),
		"one aircraft inside the altitude window enables partial release"
	)
	_check(
		controller.release_ready_bombs() == 1,
		"formation divergence does not block the release-ready aircraft"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB NO FORMATION REQUIREMENT TEST: %s" % failure)
	print(
		"DIVE_BOMB_NO_FORMATION_REQUIREMENT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
