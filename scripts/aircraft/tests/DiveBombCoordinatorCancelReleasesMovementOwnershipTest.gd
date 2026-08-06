extends SceneTree
## Coordinator cancel contract (§9, §28): cancelling from ALIGNING, DIVING
## and REGROUPING always recovers every aircraft's movement ownership, ends
## the coordinator terminally, keeps the attack statistics, and spawns no
## further projectiles.

var _failures: Array[String] = []
var _spawned_projectiles := 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _run_scenario("cancel_during_aligning", false, false)
	await _run_scenario("cancel_during_diving", true, false)
	await _run_scenario("cancel_during_regrouping", true, true)
	print(
		"DIVE_BOMB_COORDINATOR_CANCEL_OWNERSHIP_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("CANCEL OWNERSHIP: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _run_scenario(
		label: String,
		enter_dive: bool,
		enter_regroup: bool
) -> void:
	_spawned_projectiles = 0
	var battle := DiveBombContractTestSupport.spawn_battle(root)
	await physics_frame
	var squadron := DiveBombContractTestSupport.launch_frozen_squadron(battle)
	_check(squadron != null, label + ": squadron launches")
	if squadron == null:
		await _cleanup(battle)
		return
	for aircraft in squadron.aircraft_units:
		aircraft.weapon_controller.weapon_released.connect(
			func(_aircraft: AircraftUnit, projectile: Node) -> void:
				if projectile != null:
					_spawned_projectiles += 1
		)
	var target_point := squadron.formation_center + Vector3(0.0, 0.0, 1500.0)
	target_point.y = 0.0
	var coordinator := DiveBombContractTestSupport.begin_quick_attack(
		squadron,
		DiveBombContractTestSupport.make_position_request(
			target_point,
			squadron.get_team()
		)
	)
	_check(coordinator != null, label + ": coordinator starts")
	if coordinator == null:
		await _cleanup(battle)
		return
	var controllers := coordinator.get_aircraft_controllers()
	if enter_dive:
		for controller in controllers:
			DiveBombContractTestSupport.place_in_release_window(controller)
	if enter_regroup:
		for controller in controllers:
			controller.update(1.0 / 60.0)
		for _frame in 600:
			coordinator.update(1.0 / 60.0)
			if coordinator.state \
					== SquadronDiveBombCoordinator.State.REGROUPING:
				break
		_check(
			coordinator.state \
				== SquadronDiveBombCoordinator.State.REGROUPING,
			label + ": precondition regrouping reached"
		)
	var released_before := coordinator.released_count
	var projectiles_before := _spawned_projectiles
	coordinator.cancel(&"player_override")
	_check(
		coordinator.state == SquadronDiveBombCoordinator.State.CANCELLED \
			or (
				enter_regroup and not coordinator.is_active()
			),
		label + ": coordinator ends terminally"
	)
	_check(
		not coordinator.is_active(),
		label + ": coordinator is inactive after cancel"
	)
	_check(
		coordinator.released_count == released_before,
		label + ": released statistics survive the cancel"
	)
	for aircraft in squadron.get_alive_aircraft():
		_check(
			aircraft.is_movement_owned_by(
				AircraftMovementOwner.Type.FORMATION
			),
			label + ": every aircraft returns to FORMATION"
		)
	for controller in controllers:
		controller.update(1.0 / 60.0)
	_check(
		_spawned_projectiles == projectiles_before,
		label + ": no projectile spawns after the cancel"
	)
	await _cleanup(battle)


func _cleanup(battle: BattleScene) -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
