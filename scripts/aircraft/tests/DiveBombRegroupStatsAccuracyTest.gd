extends SceneTree
## Regroup statistics contract (§14-18, §27): the recorded regrouped count is
## the ACTUAL number of aircraft inside the split horizontal/altitude
## tolerances, the completion reason names the real cause with the documented
## priority, a timeout neither inflates the stats nor fails a successful
## attack, and every ownership returns to formation.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _run_scenario("ratio_completion", true)
	await _run_scenario("timeout_completion", false)
	print(
		"DIVE_BOMB_REGROUP_STATS_ACCURACY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("REGROUP STATS: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _run_scenario(label: String, move_aircraft_to_rally: bool) -> void:
	var battle := DiveBombContractTestSupport.spawn_battle(root)
	await physics_frame
	var squadron := DiveBombContractTestSupport.launch_frozen_squadron(battle)
	_check(squadron != null, label + ": squadron launches")
	if squadron == null:
		await _cleanup(battle)
		return
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
	for controller in controllers:
		DiveBombContractTestSupport.place_in_release_window(controller)
		controller.update(1.0 / 60.0)
		_check(
			controller.attack_state.released,
			label + ": precondition all aircraft release"
		)
	# Drive pull-out to completion so the coordinator begins the regroup.
	for _frame in 900:
		for controller in controllers:
			controller.update(1.0 / 60.0)
		coordinator.update(1.0 / 60.0)
		if coordinator.state == SquadronDiveBombCoordinator.State.REGROUPING:
			break
	_check(
		coordinator.state == SquadronDiveBombCoordinator.State.REGROUPING,
		label + ": regroup begins after the attack"
	)
	if coordinator.state != SquadronDiveBombCoordinator.State.REGROUPING:
		await _cleanup(battle)
		return
	for aircraft in squadron.get_alive_aircraft():
		_check(
			aircraft.is_movement_owned_by(
				AircraftMovementOwner.Type.FORMATION
			),
			label + ": regrouping aircraft are formation-controlled"
		)
	var dive_data := squadron.get_dive_bomber_combat_data()
	var rally: Vector3 = coordinator._regroup_position
	if move_aircraft_to_rally:
		# Aircraft over the rally point but still climbing: horizontal is
		# satisfied, altitude within the authored tolerance.
		for aircraft in squadron.get_alive_aircraft():
			aircraft.global_position = rally + Vector3(
				10.0,
				-dive_data.regroup_altitude_tolerance_m * 0.5,
				10.0
			)
		coordinator.update(1.0 / 60.0)
		_check(
			coordinator.regroup_completion_reason \
				== SquadronDiveBombCoordinator.RegroupCompletionReason \
					.RATIO_REACHED,
			label + ": completion reason is RATIO_REACHED"
		)
		var alive_count := squadron.get_alive_aircraft().size()
		_check(
			coordinator.regrouped_count == alive_count \
				and coordinator.regroup_arrived_count == alive_count,
			label + ": the arrived count matches reality"
		)
		_check(
			coordinator.state \
				== SquadronDiveBombCoordinator.State.COMPLETED,
			label + ": a released attack completes"
		)
	else:
		# Nobody reaches the rally: only the timeout can end the regroup,
		# and it must record ZERO arrivals, not the survivor count.
		for aircraft in squadron.get_alive_aircraft():
			aircraft.global_position = rally + Vector3(
				dive_data.regroup_horizontal_tolerance_m * 10.0,
				0.0,
				0.0
			)
		var timeout_budget := int(
			maxf(dive_data.regroup_timeout_sec, 0.0) * 60.0
		) + 10
		for _frame in timeout_budget:
			coordinator.update(1.0 / 60.0)
			if coordinator.state \
					!= SquadronDiveBombCoordinator.State.REGROUPING:
				break
		_check(
			coordinator.regroup_completion_reason \
				== SquadronDiveBombCoordinator.RegroupCompletionReason \
					.TIMEOUT,
			label + ": completion reason is TIMEOUT"
		)
		_check(
			coordinator.regrouped_count == 0,
			label + ": a timeout records the real arrivals, not alive count "
				+ "(got %d)" % coordinator.regrouped_count
		)
		_check(
			coordinator.state \
				== SquadronDiveBombCoordinator.State.COMPLETED,
			label + ": a timeout does not fail a released attack"
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
