extends SceneTree
## Partial success contract (§23): aircraft release independently. One
## aircraft's missed window neither stops the others nor consumes its bomb,
## and the coordinator's stats separate released from failed.

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

	# A releases first, B later, C misses its window entirely.
	var first := controllers[0]
	DiveBombContractTestSupport.place_in_release_window(first)
	first.update(1.0 / 60.0)
	_check(
		first.attack_state.released,
		"the first aircraft releases on its own window"
	)
	var late := controllers[1]
	_check(
		not late.attack_state.released,
		"the second aircraft has not released yet"
	)
	var missed := controllers[2]
	var missed_aircraft := missed.attack_state.get_aircraft()
	var missed_ammunition := \
		missed_aircraft.weapon_controller.get_remaining_ammunition()
	# Drop C below the minimum release altitude without a valid window: its
	# pass is abandoned, the bomb stays aboard.
	DiveBombContractTestSupport.place_in_release_window(missed)
	missed_aircraft.global_position.y = \
		missed.attack_state.solution.final_aim_impact_position.y \
		+ missed.dive_data.minimum_release_altitude_m - 5.0
	missed.update(1.0 / 60.0)
	_check(
		not missed.attack_state.released,
		"a missed window never releases"
	)
	_check(
		missed.attack_state.state \
			== DiveBombAircraftAttackState.State.PULLING_OUT,
		"a missed window pulls out"
	)
	_check(
		missed_aircraft.weapon_controller.get_remaining_ammunition() \
			== missed_ammunition,
		"a missed window keeps the bomb aboard"
	)
	# B still gets its normal window afterwards.
	DiveBombContractTestSupport.place_in_release_window(late)
	late.update(1.0 / 60.0)
	_check(
		late.attack_state.released,
		"the failed aircraft does not stop the later one"
	)
	# Release the remaining aircraft to settle the counts.
	for index in range(3, controllers.size()):
		DiveBombContractTestSupport.place_in_release_window(controllers[index])
		controllers[index].update(1.0 / 60.0)
	coordinator.update(1.0 / 60.0)
	var expected_released := controllers.size() - 1
	_check(
		coordinator.released_count == expected_released,
		"released_count counts only real releases (got %d, want %d)"
			% [coordinator.released_count, expected_released]
	)
	coordinator.cancel(&"test_finished")
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_PARTIAL_AIRCRAFT_RELEASE_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
