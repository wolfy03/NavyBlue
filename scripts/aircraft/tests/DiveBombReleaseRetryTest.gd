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
	var squadron := _launch_test_squadron(battle)
	if squadron == null:
		await _finish(battle)
		return
	var aircraft := squadron.get_alive_aircraft()
	for index in range(1, aircraft.size()):
		aircraft[index].weapon_controller.remaining_ammunition = 0
		aircraft[index].global_position = Vector3(
			float(index) * 20.0,
			120.0,
			200.0
		)
	aircraft[0].weapon_controller.release_cooldown_left = 0.08
	aircraft[0].global_position = Vector3(0.0, 95.0, 200.0)
	var controller := squadron.dive_bomb_controller
	controller.maximum_release_retry_count = 3
	controller.release_retry_interval_sec = 0.05
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"retry test dive starts"
	)
	controller.dive_elapsed_seconds = 1.0
	controller.update_dive(0.0)
	controller.update_dive(0.0)
	_check(
		controller.get_aircraft_release_state(aircraft[0]) \
			== DiveBombAttackController.AircraftReleaseState.PENDING,
		"temporary cooldown keeps release pending"
	)
	_check(
		int(controller.get_debug_snapshot().aircraft_retry_counts.get(
			aircraft[0].get_instance_id(),
			0
		)) == 1,
		"temporary failure records one retry"
	)
	squadron._update_aircraft_weapon_releases(0.1)
	controller.update_dive(0.1)
	_check(
		controller.get_aircraft_release_state(aircraft[0]) \
			== DiveBombAttackController.AircraftReleaseState.REQUESTED,
		"release is retried after cooldown expires"
	)
	squadron._update_aircraft_weapon_releases(0.0)
	_check(
		controller.get_aircraft_release_state(aircraft[0]) \
			== DiveBombAttackController.AircraftReleaseState.RELEASED,
		"retried request succeeds after projectile creation"
	)
	controller.update_dive(0.0)
	var last_result := squadron.get_last_release_result()
	_check(
		int(last_result.get("released_count", 0)) == 1,
		"last release result preserves retry success"
	)
	await _finish(battle)


func _launch_test_squadron(battle: BattleScene) -> AircraftSquadron:
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
		push_error("DIVE BOMB RELEASE RETRY TEST: %s" % failure)
	print(
		"DIVE_BOMB_RELEASE_RETRY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
