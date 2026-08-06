extends SceneTree
## Release retry contract (§5): a transient per-aircraft release refusal is
## retried a bounded number of times inside the open window; recovery before
## the limit still drops the bomb, exhaustion abandons the pass with the
## ammunition kept aboard. Retries are independent per aircraft.

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
	_check(controllers.size() >= 2, "at least two aircraft controllers")
	if controllers.size() < 2:
		await _finish(battle)
		return

	# --- Recovery inside the retry budget drops the bomb.
	var recovering := controllers[0]
	var recovering_aircraft := recovering.attack_state.get_aircraft()
	DiveBombContractTestSupport.place_in_release_window(recovering)
	var ammunition_before := \
		recovering_aircraft.weapon_controller.get_remaining_ammunition()
	recovering_aircraft.weapon_controller.disable_weapon_release()
	recovering.update(1.0 / 60.0)
	_check(
		recovering.attack_state.release_retry_count == 1,
		"a refused release counts one retry"
	)
	_check(
		recovering.attack_state.state \
			== DiveBombAircraftAttackState.State.DIVING,
		"a refused release keeps diving inside the retry budget"
	)
	_check(
		recovering_aircraft.weapon_controller.get_remaining_ammunition() \
			== ammunition_before,
		"a refused release consumes no ammunition"
	)
	recovering_aircraft.weapon_controller._release_enabled = true
	# Wait out the retry cooldown, then the next window pass must release.
	var recovered := false
	for _attempt in 60:
		recovering.update(1.0 / 60.0)
		if recovering.attack_state.released:
			recovered = true
			break
	_check(recovered, "recovery before the retry limit still releases")
	_check(
		recovering.attack_state.ammunition_consumed,
		"the recovered release consumes ammunition"
	)

	# --- Exhaustion abandons the pass, bomb kept aboard.
	var exhausted := controllers[1]
	var exhausted_aircraft := exhausted.attack_state.get_aircraft()
	DiveBombContractTestSupport.place_in_release_window(exhausted)
	var exhausted_ammunition := \
		exhausted_aircraft.weapon_controller.get_remaining_ammunition()
	exhausted_aircraft.weapon_controller.disable_weapon_release()
	for _attempt in 240:
		exhausted.update(1.0 / 60.0)
		if exhausted.attack_state.state \
				!= DiveBombAircraftAttackState.State.DIVING:
			break
	_check(
		exhausted.attack_state.release_block_reason \
			== DiveBombReleaseBlockReason.Type.RELEASE_RETRY_EXHAUSTED,
		"exhausting the retries records RELEASE_RETRY_EXHAUSTED"
	)
	_check(
		exhausted.attack_state.state \
			== DiveBombAircraftAttackState.State.PULLING_OUT,
		"exhausting the retries pulls out"
	)
	_check(
		not exhausted.attack_state.released,
		"an exhausted pass never fakes a release"
	)
	_check(
		exhausted_aircraft.weapon_controller.get_remaining_ammunition() \
			== exhausted_ammunition,
		"an exhausted pass keeps the bomb aboard"
	)
	_check(
		exhausted.attack_state.release_retry_count \
			> recovering.attack_state.release_retry_count,
		"retry counters are independent per aircraft"
	)
	coordinator.cancel(&"test_finished")
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_INDIVIDUAL_RELEASE_RETRY_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
