extends SceneTree
## Aircraft destroyed mid-attack (§24): the killed aircraft resolves to
## DESTROYED, the surviving controllers keep attacking normally, no stale
## movement ownership or callbacks leak, and the coordinator never waits on
## the dead aircraft.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := DiveBombContractTestSupport.spawn_battle(root)
	await physics_frame
	var squadron := DiveBombContractTestSupport.launch_frozen_squadron(battle)
	_check(squadron != null, "squadron launches")
	if squadron == null:
		await _finish(battle)
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
	_check(coordinator != null, "quick attack coordinator starts")
	if coordinator == null:
		await _finish(battle)
		return
	var controllers := coordinator.get_aircraft_controllers()
	_check(controllers.size() >= 3, "at least three aircraft controllers")
	if controllers.size() < 3:
		await _finish(battle)
		return

	# --- Kill one aircraft while DIVING, before its release.
	var doomed := controllers[0]
	var doomed_aircraft := doomed.attack_state.get_aircraft()
	DiveBombContractTestSupport.place_in_release_window(doomed)
	doomed_aircraft.health.apply_damage(999999.0)
	doomed.update(1.0 / 60.0)
	_check(
		doomed.attack_state.state \
			== DiveBombAircraftAttackState.State.DESTROYED,
		"a killed diving aircraft resolves to DESTROYED"
	)
	_check(
		doomed.attack_state.release_block_reason \
			== DiveBombReleaseBlockReason.Type.AIRCRAFT_DESTROYED,
		"the destruction is recorded as the block reason"
	)
	_check(
		not doomed.attack_state.released,
		"a destroyed aircraft never counts as released"
	)

	# --- Kill another during pull-out after a successful release.
	var pull_out_victim := controllers[1]
	DiveBombContractTestSupport.place_in_release_window(pull_out_victim)
	pull_out_victim.update(1.0 / 60.0)
	_check(
		pull_out_victim.attack_state.released,
		"precondition: the second aircraft released"
	)
	var victim_aircraft := pull_out_victim.attack_state.get_aircraft()
	victim_aircraft.health.apply_damage(999999.0)
	pull_out_victim.update(1.0 / 60.0)
	_check(
		pull_out_victim.attack_state.state \
			== DiveBombAircraftAttackState.State.DESTROYED,
		"a killed pulling-out aircraft resolves to DESTROYED"
	)
	_check(
		pull_out_victim.attack_state.released,
		"its earlier successful release is preserved in the stats"
	)

	# --- Every survivor is unaffected and the coordinator keeps counting.
	for survivor_index in range(2, controllers.size()):
		var survivor := controllers[survivor_index]
		DiveBombContractTestSupport.place_in_release_window(survivor)
		survivor.update(1.0 / 60.0)
		_check(
			survivor.attack_state.released,
			"a surviving aircraft still attacks normally"
		)
	coordinator.update(1.0 / 60.0)
	_check(
		coordinator.destroyed_count == 2,
		"the coordinator counts both destroyed aircraft (got %d)"
			% coordinator.destroyed_count
	)
	var expected_released := controllers.size() - 1
	_check(
		coordinator.released_count == expected_released,
		"released stats keep the pre-destruction release (got %d, want %d)"
			% [coordinator.released_count, expected_released]
	)
	_check(
		coordinator.state != SquadronDiveBombCoordinator.State.ALIGNING \
			and coordinator.state != SquadronDiveBombCoordinator.State.DIVING,
		"the coordinator does not wait forever on dead aircraft"
	)
	coordinator.cancel(&"test_finished")
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	await process_frame
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_AIRCRAFT_DESTROYED_DURING_RELEASE_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
