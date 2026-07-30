extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []
var _sequence_completed_count := 0
var _sequence_released_count := 0


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
	squadron.dive_release_pass_finished.connect(
		_on_release_pass_finished
	)
	var attack_target := _find_hostile_ship(battle, carrier)
	_check(attack_target != null, "manual dive test finds a hostile target")
	if attack_target != null:
		attack_target.set_physics_process(false)
		attack_target.global_position = Vector3.ZERO
		attack_target.velocity = Vector3(10.0, 0.0, 0.0)
	squadron.formation_center = Vector3(0.0, 180.0, 80.0)
	_align_aircraft_with_formation(squadron)
	_check(
		squadron.issue_player_move_command(
			Vector3.ZERO,
			attack_target
		),
		"player move prepares a manual dive"
	)
	squadron.formation_center = Vector3(0.0, 180.0, 80.0)
	_align_aircraft_with_formation(squadron)
	var ammunition_before := squadron.get_total_remaining_ammunition()
	_check(squadron.begin_manual_dive(), "one action begins the dive")
	squadron._update_player_dive_target()
	var predicted_target_once := \
		squadron.dive_bomb_controller.target_position
	squadron._update_player_dive_target()
	_check(
		squadron.dive_bomb_controller.target_position \
			== predicted_target_once,
		"moving target prediction is applied once per update"
	)
	var state_after_first_input := squadron.get_dive_attack_state()
	_check(
		not squadron.begin_manual_dive(),
		"repeated input is ignored while the dive is active"
	)
	_check(
		squadron.get_dive_attack_state() == state_after_first_input,
		"repeated input does not change the controller state"
	)
	_check(
		squadron.get_total_remaining_ammunition() == ammunition_before,
		"beginning a dive does not release bombs immediately"
	)

	var release_state_seen := false
	var pull_out_seen := false
	var previous_state := int(squadron.get_dive_attack_state())
	for _index in 600:
		_advance_dive(squadron, 1.0 / 60.0)
		var current_state := int(squadron.get_dive_attack_state())
		_check(
			current_state >= previous_state,
			"dive state never moves backward"
		)
		previous_state = current_state
		release_state_seen = release_state_seen \
			or current_state == DiveBombAttackController.State.RELEASING
		pull_out_seen = pull_out_seen \
			or current_state == DiveBombAttackController.State.PULLING_OUT
		if current_state == DiveBombAttackController.State.COMPLETED:
			break

	_check(release_state_seen, "automatic altitude starts release sequence")
	_check(
		_sequence_completed_count == 1,
		"release sequence completion is emitted exactly once"
	)
	_check(
		_sequence_released_count == squadron.get_alive_aircraft_count(),
		"every release-capable survivor actually releases"
	)
	_check(
		squadron.get_total_remaining_ammunition() < ammunition_before,
		"automatic release consumes sortie ammunition"
	)
	_check(
		pull_out_seen,
		"pull-out begins after release sequence completion"
	)
	_check(
		squadron.dive_bomb_controller.state \
			== DiveBombAttackController.State.COMPLETED,
		"dive controller completes pull-out"
	)
	_check(
		squadron.state == AircraftSquadron.State.HOLDING,
		"manual dive returns to holding instead of auto-returning"
	)
	for aircraft in squadron.get_alive_aircraft():
		_check(
			aircraft.movement.flight_mode \
				== AircraftMovement.FlightMode.FORMATION,
			"completed pull-out restores formation flight"
		)
	await _finish(battle)


func _advance_dive(
		squadron: AircraftSquadron,
		delta: float
) -> void:
	squadron.payload_release_coordinator.update(delta)
	squadron.dive_bomb_controller.update_dive(delta)
	for aircraft in squadron.get_alive_aircraft():
		aircraft.movement.update_movement(delta)


func _align_aircraft_with_formation(
		squadron: AircraftSquadron
) -> void:
	for aircraft in squadron.get_alive_aircraft():
		aircraft.global_position = squadron.formation_center \
			+ aircraft.formation_offset


func _on_release_pass_finished(
		released_count: int,
		_failed_count: int,
		_skipped_count: int,
		_cancelled: bool
) -> void:
	_sequence_completed_count += 1
	_sequence_released_count = released_count


func _find_hostile_ship(
		battle: BattleScene,
		carrier: ShipUnit
) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null and carrier.is_hostile_to(ship):
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("DIVE BOMB ATTACK CONTROLLER TEST: %s" % failure)
	print(
		"DIVE_BOMB_ATTACK_CONTROLLER_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
