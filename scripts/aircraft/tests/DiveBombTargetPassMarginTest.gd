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
	squadron._formation_forward = Vector3(0.0, 0.0, -1.0)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	var controller := squadron.dive_bomb_controller
	controller.target_position = Vector3.ZERO
	controller.dive_data.target_pass_margin_m = 75.0
	controller.dive_data.target_pass_check_max_altitude_m = 160.0
	controller.dive_data.require_release_attempt_before_pass_abort = true

	_set_aircraft_positions(squadron, -50.0, 120.0)
	_check(
		controller._has_passed_target(),
		"target is geometrically behind the squadron"
	)
	_check(
		not controller._should_abort_after_passing_target(),
		"target pass margin prevents a near-target abort"
	)
	_set_aircraft_positions(squadron, -200.0, 120.0)
	_check(
		not controller._should_abort_after_passing_target(),
		"passing target before a release attempt does not abort"
	)
	controller._total_release_request_count = 1
	_set_aircraft_positions(squadron, -200.0, 220.0)
	_check(
		not controller._should_abort_after_passing_target(),
		"high-altitude target crossing does not abort"
	)
	_set_aircraft_positions(squadron, -200.0, 120.0)
	_check(
		controller._should_abort_after_passing_target(),
		"target crossing beyond margin at release altitude aborts"
	)
	await _finish(battle)


func _set_aircraft_positions(
		squadron: AircraftSquadron,
		z_position: float,
		y_position: float
) -> void:
	for index in squadron.aircraft_units.size():
		squadron.aircraft_units[index].global_position = Vector3(
			float(index) * 10.0,
			y_position,
			z_position
		)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB TARGET PASS MARGIN TEST: %s" % failure)
	print(
		"DIVE_BOMB_TARGET_PASS_MARGIN_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
