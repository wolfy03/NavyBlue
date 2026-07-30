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
	var alive := squadron.get_alive_aircraft()
	squadron.formation_center = Vector3(0.0, 300.0, 300.0)
	squadron._formation_forward = Vector3(0.0, 0.0, -1.0)
	for index in alive.size():
		alive[index].global_position = Vector3(
			float(index) * 250.0,
			95.0,
			300.0 + float(index % 2) * 220.0
		)
	var controller := squadron.dive_bomb_controller
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"formation-independent dive starts"
	)
	controller.dive_elapsed_seconds = 1.0
	controller.update_dive(0.0)
	controller.update_dive(0.0)
	for aircraft in alive:
		_check(
			controller.get_aircraft_release_state(aircraft) \
				== DiveBombAttackController.AircraftReleaseState.REQUESTED,
			"formation position does not block an aircraft at release altitude"
		)
	_check(
		squadron.payload_release_coordinator.get_active_requested_count() \
			== alive.size(),
		"each aircraft has its own tracked release request"
	)
	controller.cancel()
	_check(
		not squadron.is_weapon_release_in_progress(),
		"cancel safely resolves all individual requests"
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
