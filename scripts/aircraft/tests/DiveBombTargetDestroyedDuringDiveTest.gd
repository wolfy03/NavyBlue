extends SceneTree
## Target destroyed during the dive (§25): after the solution lock, the loss
## of the target ship never retargets or aborts the committed dive - the
## bomb is still released at the locked final aim point.

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
	var target := _find_enemy(battle)
	_check(target != null, "a hostile target exists")
	if target == null:
		await _finish(battle)
		return
	target.set_physics_process(false)
	target.global_position = squadron.formation_center \
		+ Vector3(0.0, 0.0, 1500.0)
	target.global_position.y = 0.0
	var coordinator := DiveBombContractTestSupport.begin_quick_attack(
		squadron,
		DiveBombContractTestSupport.make_ship_request(
			target,
			squadron.get_team()
		)
	)
	_check(coordinator != null, "quick attack coordinator starts")
	if coordinator == null:
		await _finish(battle)
		return
	var controllers := coordinator.get_aircraft_controllers()
	_check(not controllers.is_empty(), "controllers exist")
	if controllers.is_empty():
		await _finish(battle)
		return
	var diver := controllers[0]
	var locked_aim: Vector3 = diver.attack_state.solution \
		.final_aim_impact_position
	var locked_direction: Vector3 = diver.attack_state.locked_attack_direction
	DiveBombContractTestSupport.place_in_release_window(diver)

	# The target dies mid-dive, after the lock.
	target.queue_free()
	await process_frame
	diver.update(1.0 / 60.0)
	_check(
		diver.attack_state.released,
		"the committed dive still releases after target loss"
	)
	_check(
		diver.attack_state.solution.final_aim_impact_position == locked_aim,
		"the locked final aim is never replaced"
	)
	_check(
		diver.attack_state.locked_attack_direction == locked_direction,
		"the locked dive direction is never replaced"
	)
	coordinator.cancel(&"test_finished")
	await _finish(battle)


func _find_enemy(battle: BattleScene) -> ShipUnit:
	for ship_value in battle.enemies:
		var ship := ship_value as ShipUnit
		if ship != null and is_instance_valid(ship):
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	await process_frame
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_TARGET_DESTROYED_DURING_DIVE_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
