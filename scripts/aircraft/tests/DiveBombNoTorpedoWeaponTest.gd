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
		var weapon_copy := aircraft.weapon_controller.weapon_data \
			.duplicate(true) as AircraftWeaponData
		weapon_copy.weapon_type = AircraftWeaponData.WeaponType.TORPEDO
		aircraft.weapon_controller.weapon_data = weapon_copy
	var controller := squadron.dive_bomb_controller
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"torpedo-equipped dive-bomber attack can fail safely"
	)
	for aircraft in squadron.get_alive_aircraft():
		_check(
			controller.get_aircraft_release_state(aircraft) \
				== DiveBombAttackController.AircraftReleaseState.SKIPPED,
			"torpedo payload is skipped by dive-bomb controller"
		)
	_check(
		squadron.get_release_sequence_queued_count() == 0,
		"no torpedo payload release is queued"
	)
	controller.cancel()
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB NO TORPEDO TEST: %s" % failure)
	print(
		"DIVE_BOMB_NO_TORPEDO_WEAPON_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
