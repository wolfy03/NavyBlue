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
	for index in alive.size():
		alive[index].global_position = Vector3(
			float(index) * 140.0,
			70.0 + float(index) * 75.0,
			float(index % 2) * 200.0
		)
	var queued_count := squadron.request_weapon_release_for_dive(
		Vector3.ZERO,
		Vector3.ZERO
	)
	_check(
		queued_count == alive.size(),
		"formation divergence does not filter dive release aircraft"
	)
	_check(
		squadron.get_release_sequence_queued_count() == alive.size(),
		"release sequence preserves every release-capable survivor"
	)
	squadron.cancel_pending_weapon_release()
	_check(
		not squadron.is_weapon_release_in_progress(),
		"cancel safely clears the formation-independent queue"
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
