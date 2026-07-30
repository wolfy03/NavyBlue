extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []
var _individual_success_count := 0
var _pass_completed_count := 0
var _pass_released_count := 0


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
	squadron.formation_center = Vector3(0.0, 180.0, 200.0)
	squadron._formation_forward = Vector3(0.0, 0.0, -1.0)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	var aircraft := squadron.get_alive_aircraft()
	for index in range(1, aircraft.size()):
		aircraft[index].weapon_controller.remaining_ammunition = 0
		aircraft[index].global_position.y = 120.0
	aircraft[0].global_position = Vector3(0.0, 95.0, 200.0)
	var controller := squadron.dive_bomb_controller
	controller.aircraft_automatic_release_completed.connect(
		func(
			_aircraft_id: int,
			_released_count: int,
			_total_count: int
		) -> void:
			_individual_success_count += 1
	)
	controller.automatic_release_pass_completed.connect(
		func(
			released_count: int,
			_failed_count: int,
			_skipped_count: int,
			_cancelled: bool
		) -> void:
			_pass_completed_count += 1
			_pass_released_count = released_count
	)
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"signal-semantics dive starts"
	)
	controller.dive_elapsed_seconds = 1.0
	controller.update_dive(0.0)
	controller.update_dive(0.0)
	_check(
		_individual_success_count == 0,
		"request registration is not reported as a successful release"
	)
	squadron.payload_release_coordinator.update(0.0)
	_check(
		_individual_success_count == 1,
		"actual projectile creation emits one individual success"
	)
	controller.update_dive(0.0)
	var result := squadron.get_last_payload_release_result()
	_check(
		_pass_completed_count == 1,
		"whole release pass completion emits once"
	)
	_check(
		_pass_released_count == 1,
		"pass completion reports one actual release"
	)
	_check(
		result.released_count == 1,
		"Squadron authoritative result records one release"
	)
	_check(
		controller.get_attack_result_data().released_count == 1,
		"Controller result matches Squadron actual release count"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB RELEASE SIGNAL TEST: %s" % failure)
	print(
		"DIVE_BOMB_RELEASE_SIGNAL_SEMANTICS_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
