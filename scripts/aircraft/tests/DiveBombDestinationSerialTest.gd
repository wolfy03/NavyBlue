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
	var destination := Vector3(500.0, 180.0, 500.0)
	var first_serial := squadron.set_mission_destination(destination)
	_check(first_serial > 0, "new destination receives a command serial")
	squadron._mission_destination_reached = true
	squadron._reached_destination_serial = first_serial
	squadron.state = AircraftSquadron.State.HOLDING
	_check(
		squadron.has_reached_mission_destination(first_serial),
		"arrival is recorded for the matching command serial"
	)
	var same_serial := squadron.set_mission_destination(
		destination + Vector3(1.0, 0.0, 0.0)
	)
	_check(
		same_serial == first_serial,
		"equivalent destination reuses the command serial"
	)
	_check(
		squadron.has_reached_mission_destination(first_serial),
		"equivalent destination preserves its arrival result"
	)
	var forced_serial := squadron.set_mission_destination(destination, true)
	_check(
		forced_serial > first_serial,
		"forced same-position command creates a new serial"
	)
	_check(
		not squadron.has_reached_mission_destination(forced_serial),
		"new serial does not inherit prior arrival"
	)
	_check(
		not squadron.has_reached_mission_destination(first_serial),
		"old serial is no longer the active reached destination"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB DESTINATION SERIAL TEST: %s" % failure)
	print(
		"DIVE_BOMB_DESTINATION_SERIAL_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
