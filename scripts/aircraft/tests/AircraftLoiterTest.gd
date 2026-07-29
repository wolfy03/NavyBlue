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
		"basic_fighter_squadron"
	)
	_check(squadron != null, "manual fighter squadron launches")
	if squadron != null:
		squadron.set_physics_process(false)
		for aircraft in squadron.aircraft_units:
			aircraft.activate()
		var center := Vector3(500.0, 220.0, 500.0)
		squadron.destination = center
		squadron.formation_center = center
		squadron._begin_loiter()
		var before := squadron.formation_center
		for _index in 20:
			squadron._update_loiter(0.1)
		_check(
			squadron.state == AircraftSquadron.State.HOLDING,
			"loiter keeps the squadron in holding state"
		)
		_check(
			squadron.formation_center.distance_to(before) > 1.0,
			"holding squadron continues flying instead of stopping"
		)
		var radius := Vector2(
			squadron.formation_center.x - center.x,
			squadron.formation_center.z - center.z
		).length()
		_check(
			radius > 1.0 \
				and radius \
					<= squadron.squadron_data.loiter_radius_m * 1.5,
			"loiter remains around the commanded destination"
		)
		squadron._update_aircraft_formation_targets()
		var unit := squadron.get_alive_aircraft()[0]
		unit.global_position = unit.movement.target_position
		unit.movement.update_movement(0.1)
		_check(
			unit.velocity.length() > 0.0,
			"formation follower keeps minimum forward speed at its target"
		)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("AIRCRAFT LOITER TEST: %s" % failure)
	print(
		"AIRCRAFT_LOITER_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
