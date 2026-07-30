extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []
var _projectile_release_count := 0


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
		aircraft.weapon_controller.weapon_released.connect(
			_on_weapon_released
		)
	var aircraft := squadron.get_alive_aircraft()
	squadron.formation_center = Vector3(0.0, 180.0, 200.0)
	squadron._formation_forward = Vector3(0.0, 0.0, -1.0)
	var altitudes := [95.0, 130.0, 160.0, 190.0]
	for index in aircraft.size():
		aircraft[index].global_position = Vector3(
			float(index) * 120.0,
			altitudes[index],
			200.0 + float(index % 2) * 140.0
		)
	var controller := squadron.dive_bomb_controller
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"individual release dive starts"
	)
	controller.dive_elapsed_seconds = 1.0
	controller.update_dive(0.0)
	controller.update_dive(0.0)
	_check(
		controller.get_aircraft_release_state(aircraft[0]) \
			== DiveBombAttackController.AircraftReleaseState.REQUESTED,
		"only the lowest aircraft requests release first"
	)
	for index in range(1, aircraft.size()):
		_check(
			controller.get_aircraft_release_state(aircraft[index]) \
				== DiveBombAttackController.AircraftReleaseState.PENDING,
			"higher aircraft remains pending"
		)
	_check(
		_projectile_release_count == 0,
		"request acceptance is not projectile completion"
	)
	squadron.payload_release_coordinator.update(0.0)
	_check(
		controller.get_aircraft_release_state(aircraft[0]) \
			== DiveBombAttackController.AircraftReleaseState.RELEASED,
		"actual projectile creation marks the first aircraft released"
	)
	_check(
		_projectile_release_count == 1,
		"only one projectile is created for the first threshold crossing"
	)
	controller.update_dive(0.0)
	squadron.payload_release_coordinator.update(0.0)
	_check(
		_projectile_release_count == 1,
		"the same aircraft cannot release twice in one attack pass"
	)
	aircraft[1].global_position.y = 95.0
	controller.update_dive(0.0)
	_check(
		controller.get_aircraft_release_state(aircraft[1]) \
			== DiveBombAttackController.AircraftReleaseState.REQUESTED,
		"second aircraft requests only after reaching its own altitude"
	)
	squadron.payload_release_coordinator.update(0.0)
	_check(
		controller.get_aircraft_release_state(aircraft[1]) \
			== DiveBombAttackController.AircraftReleaseState.RELEASED,
		"second aircraft independently completes release"
	)
	_check(
		_projectile_release_count == 2,
		"different aircraft altitudes produce staggered projectiles"
	)
	controller.cancel()
	await _finish(battle)


func _on_weapon_released(
		_aircraft: AircraftUnit,
		_projectile: Node
) -> void:
	_projectile_release_count += 1


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB INDIVIDUAL RELEASE TEST: %s" % failure)
	print(
		"DIVE_BOMB_INDIVIDUAL_AUTOMATIC_RELEASE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
