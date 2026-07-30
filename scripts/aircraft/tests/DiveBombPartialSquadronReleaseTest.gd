extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []
var _completion_count := 0
var _completed_queued_count := 0
var _completed_released_count := 0


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
	squadron.weapon_release_sequence_completed.connect(
		_on_release_sequence_completed
	)
	var aircraft := squadron.get_alive_aircraft()
	for index in aircraft.size():
		aircraft[index].global_position = Vector3(
			float(index) * 90.0,
			80.0 if index < 2 else 210.0,
			0.0
		)
	var ammunition_before := squadron.get_total_remaining_ammunition()
	var queued_count := squadron.request_weapon_release_for_dive(
		Vector3.ZERO,
		Vector3.ZERO
	)
	_check(
		queued_count == aircraft.size(),
		"dive release queues all release-capable survivors"
	)
	_check(
		squadron.get_total_remaining_ammunition() == ammunition_before,
		"queue registration is not treated as completed release"
	)
	_check(
		_completion_count == 0,
		"completion signal is not emitted when aircraft are only queued"
	)
	_drain_release_sequence(squadron)
	_check(
		_completion_count == 1,
		"release sequence emits completion exactly once"
	)
	_check(
		_completed_queued_count == aircraft.size(),
		"completion reports the queued aircraft count"
	)
	_check(
		_completed_released_count == aircraft.size(),
		"completion reports the actual releasing aircraft count"
	)
	_check(
		not squadron.is_weapon_release_in_progress(),
		"release sequence becomes inactive after completion"
	)
	await _finish(battle)


func _drain_release_sequence(squadron: AircraftSquadron) -> void:
	for _index in 32:
		squadron._update_weapon_release_sequence(0.25)
		for aircraft in squadron.get_alive_aircraft():
			aircraft.weapon_controller.update_weapon(0.25)
		if not squadron.is_weapon_release_in_progress():
			return


func _on_release_sequence_completed(
		queued_count: int,
		released_count: int
) -> void:
	_completion_count += 1
	_completed_queued_count = queued_count
	_completed_released_count = released_count


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB RELEASE SEQUENCE TEST: %s" % failure)
	print(
		"DIVE_BOMB_RELEASE_SEQUENCE_COMPLETION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
