extends SceneTree
## Solution lock and target-destroyed-after-lock contract: ALIGNING may track
## the selected target. After every aircraft physically
## enters DIVING, target motion/loss and newly appearing ships change neither
## the locked dive direction nor the final aim point.

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
	target.velocity = Vector3.ZERO
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
	_check(coordinator != null, "quick attack locks a solution per aircraft")
	if coordinator == null:
		await _finish(battle)
		return
	var controllers := coordinator.get_aircraft_controllers()
	_check(
		controllers.size() == squadron.get_alive_aircraft().size(),
		"every armed aircraft receives its own solution"
	)
	for _frame in 600:
		coordinator.update(1.0 / 60.0)
		for aircraft_value in squadron.aircraft_units:
			var aircraft := aircraft_value as AircraftUnit
			aircraft.movement.update_movement(1.0 / 60.0)
		if _all_diving(controllers):
			break
	_check(
		_all_diving(controllers),
		"every aircraft physically aligns before the final lock"
	)
	var locked_aim := coordinator.get_final_aim_impact_position()
	var locked_directions: Array[Vector3] = []
	for controller in controllers:
		locked_directions.append(
			controller.attack_state.locked_attack_direction
		)
		_check(
			controller.attack_state.solution.final_aim_impact_position \
				== locked_aim,
			"every aircraft shares the pass-wide final aim"
		)

	# --- The target moves and a NEW hostile appears mid-dive.
	target.global_position += Vector3(400.0, 0.0, 250.0)
	var intruder := DiveBombTargetingTestSupport.spawn_ship(
		battle,
		&"enemy",
		locked_aim + Vector3(60.0, 0.0, 0.0)
	)
	for controller in controllers:
		controller.update(1.0 / 60.0)
	coordinator.update(1.0 / 60.0)
	for index in controllers.size():
		_check(
			controllers[index].attack_state.locked_attack_direction \
				== locked_directions[index],
			"target motion never changes a locked dive direction"
		)
		_check(
			controllers[index].attack_state.solution \
				.final_aim_impact_position == locked_aim,
			"target motion never changes the locked final aim"
		)
	_check(
		coordinator.get_final_aim_impact_position() == locked_aim,
		"the coordinator's pass aim stays locked"
	)

	# --- Destroying the target after lock keeps the dive on the old aim.
	target.queue_free()
	await process_frame
	for controller in controllers:
		controller.update(1.0 / 60.0)
	coordinator.update(1.0 / 60.0)
	for index in controllers.size():
		_check(
			controllers[index].attack_state.solution \
				.final_aim_impact_position == locked_aim,
			"target destruction after lock never retargets the dive"
		)
	_check(
		is_instance_valid(intruder),
		"the intruding ship is untouched by the locked pass"
	)
	coordinator.cancel(&"test_finished")
	await _finish(battle)


func _find_enemy(battle: BattleScene) -> ShipUnit:
	for ship_value in battle.enemies:
		var ship := ship_value as ShipUnit
		if ship != null and is_instance_valid(ship):
			return ship
	return null


func _all_diving(
		controllers: Array[AircraftDiveBombController]
) -> bool:
	for controller in controllers:
		if controller.attack_state.state \
				!= DiveBombAircraftAttackState.State.DIVING:
			return false
	return not controllers.is_empty()


func _finish(battle: BattleScene) -> void:
	await process_frame
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_QUICK_ATTACK_SOLUTION_LOCK_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
