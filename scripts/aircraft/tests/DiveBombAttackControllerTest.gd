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
	squadron.formation_center = Vector3(0.0, 180.0, 80.0)
	_align_aircraft_with_formation(squadron)
	_check(
		squadron.issue_player_move_command(Vector3.ZERO),
		"player move prepares a manual dive"
	)
	squadron.formation_center = Vector3(0.0, 180.0, 80.0)
	_align_aircraft_with_formation(squadron)
	var ammunition_before := squadron.get_total_remaining_ammunition()
	_check(squadron.begin_manual_dive(), "first action begins the dive")
	_check(
		squadron.get_total_remaining_ammunition() == ammunition_before,
		"beginning a dive does not release bombs"
	)
	_check(
		not squadron.request_manual_bomb_release(),
		"release is rejected before minimum dive time"
	)
	_advance_dive(squadron, 0.1)
	_advance_dive(squadron, 0.2)
	for aircraft in squadron.get_alive_aircraft():
		_check(
			aircraft.movement.flight_mode \
				== AircraftMovement.FlightMode.DIRECT_FLIGHT,
			"dive switches every aircraft to direct flight"
		)
		_check(
			aircraft.velocity.y < 0.0,
			"dive gives every aircraft downward velocity"
		)
	_check(
		not squadron.request_manual_bomb_release(),
		"release remains blocked while the dive is too early"
	)
	_advance_dive(squadron, 0.3)
	if not squadron.dive_bomb_controller.can_release_bombs():
		print(
			"DIVE RELEASE DEBUG %s"
			% squadron.dive_bomb_controller.get_debug_snapshot()
		)
	_check(
		squadron.request_manual_bomb_release(),
		"second valid action queues bomb release"
	)
	squadron._update_weapon_release_sequence(0.0)
	_check(
		squadron.get_total_remaining_ammunition() < ammunition_before,
		"manual release consumes sortie ammunition"
	)
	for _index in 80:
		_advance_dive(squadron, 0.1)
		if squadron.dive_bomb_controller.state \
				== DiveBombAttackController.State.COMPLETED:
			break
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
	squadron.dive_bomb_controller.update_dive(delta)
	for aircraft in squadron.get_alive_aircraft():
		var movement := aircraft.movement
		if movement.flight_mode \
				!= AircraftMovement.FlightMode.DIRECT_FLIGHT:
			continue
		var direction := movement.direct_flight_direction
		var speed := movement.direct_flight_speed_mps
		aircraft.velocity = direction * speed
		aircraft.global_position += aircraft.velocity * delta


func _align_aircraft_with_formation(
		squadron: AircraftSquadron
) -> void:
	for aircraft in squadron.get_alive_aircraft():
		aircraft.global_position = squadron.formation_center \
			+ aircraft.formation_offset


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
