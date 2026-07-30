extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []
var _projectile_count := 0


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
	var aircraft := squadron.aircraft_units
	for index in aircraft.size():
		aircraft[index].activate()
		aircraft[index].set_physics_process(false)
		aircraft[index].global_position = Vector3(
			float(index) * 80.0,
			95.0,
			200.0
		)
		aircraft[index].weapon_controller.weapon_released.connect(
			_on_weapon_released
		)
		if index > 0:
			aircraft[index].weapon_controller.remaining_ammunition = 0
	var controller := squadron.dive_bomb_controller
	_check(
		controller.begin_dive_with_source(
			Vector3.ZERO,
			Vector3.ZERO,
			AircraftSquadron.DiveControlSource.PLAYER
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"cancellation test dive starts"
	)
	controller.dive_elapsed_seconds = 1.0
	controller.update_dive(0.0)
	controller.update_dive(0.0)
	_check(
		squadron.is_weapon_release_in_progress(),
		"individual request is active before cancellation"
	)
	controller.cancel()
	_check(
		not squadron.is_weapon_release_in_progress(),
		"cancellation resolves every active weapon request"
	)
	_check(
		controller.state == DiveBombAttackController.State.FAILED,
		"cancelled controller cannot remain in RELEASING"
	)
	var result_before_update := squadron.get_last_payload_release_result()
	_check(
		result_before_update.cancelled,
		"last release result records cancellation"
	)
	_check(
		result_before_update.released_count == 0,
		"cancelled request is not counted as projectile success"
	)
	squadron.payload_release_coordinator.update(1.0)
	_check(
		_projectile_count == 0,
		"cancelled request cannot create a later projectile"
	)
	_check(
		squadron.get_last_payload_release_result() == result_before_update,
		"last release result survives active state cleanup"
	)
	await _finish(battle)


func _on_weapon_released(
		_aircraft: AircraftUnit,
		_projectile: Node
) -> void:
	_projectile_count += 1


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB RELEASE CANCELLATION TEST: %s" % failure)
	print(
		"DIVE_BOMB_RELEASE_CANCELLATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
