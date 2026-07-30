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
	squadron.set_mission_destination(destination)
	_check(
		not squadron.has_reached_mission_destination(),
		"new destination clears the mission arrival flag"
	)
	squadron._loiter_initialized = true
	_check(
		not squadron.has_reached_mission_destination(),
		"loiter initialization does not imply mission arrival"
	)
	squadron.destination_tracker.mark_reached(
		squadron.destination_tracker.command_serial
	)
	squadron._loiter_initialized = false
	_check(
		squadron.has_reached_mission_destination(),
		"mission arrival remains true without loiter internals"
	)
	squadron.state = AircraftSquadron.State.HOLDING
	squadron.set_mission_destination(destination + Vector3(1.0, 0.0, 0.0))
	_check(
		squadron.has_reached_mission_destination(),
		"equivalent destination does not clear arrival"
	)
	squadron.set_mission_destination(
		destination + Vector3(20.0, 0.0, 0.0)
	)
	_check(
		not squadron.has_reached_mission_destination(),
		"meaningful destination change clears arrival"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB MISSION DESTINATION TEST: %s" % failure)
	print(
		"DIVE_BOMB_MISSION_DESTINATION_STATE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
