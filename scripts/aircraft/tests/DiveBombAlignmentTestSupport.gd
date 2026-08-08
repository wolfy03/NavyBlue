extends RefCounted
class_name DiveBombAlignmentTestSupport

const DELTA := 1.0 / 60.0


static func make_quick_fixture(
		tree: SceneTree,
		yaw_degrees: float,
		turn_rate_degrees_sec: float = 45.0,
		target_velocity: Vector3 = Vector3.ZERO
) -> Dictionary:
	var battle := DiveBombContractTestSupport.spawn_battle(tree.root)
	await tree.physics_frame
	var squadron := DiveBombContractTestSupport.launch_frozen_squadron(battle)
	if squadron == null:
		return {"battle": battle}
	var dive_data := squadron.get_dive_bomber_combat_data()
	dive_data.alignment_turn_rate_degrees_sec = turn_rate_degrees_sec
	dive_data.alignment_speed_mps = 0.0
	dive_data.dive_entry_heading_tolerance_degrees = 5.0
	dive_data.maximum_dive_entry_turn_rate_degrees_sec = 8.0
	dive_data.minimum_alignment_timeout_sec = 1.0
	dive_data.alignment_timeout_multiplier = 1.5
	dive_data.maximum_alignment_timeout_sec = 6.0
	var initial_heading := Vector3.FORWARD
	for aircraft_value in squadron.aircraft_units:
		var aircraft := aircraft_value as AircraftUnit
		aircraft.global_transform.basis = Basis.looking_at(
			initial_heading,
			Vector3.UP
		)
		aircraft.velocity = initial_heading * maxf(
			aircraft.aircraft_data.cruise_speed_mps,
			1.0
		)
	var target := _find_enemy(battle)
	if target == null:
		return {"battle": battle, "squadron": squadron}
	target.set_physics_process(false)
	var desired_heading := initial_heading.rotated(
		Vector3.UP,
		deg_to_rad(yaw_degrees)
	)
	target.global_position = squadron.formation_center \
		+ desired_heading * 1500.0
	target.global_position.y = 0.0
	target.velocity = target_velocity
	var coordinator := DiveBombContractTestSupport.begin_quick_attack(
		squadron,
		DiveBombContractTestSupport.make_ship_request(
			target,
			squadron.get_team()
		)
	)
	if coordinator == null or coordinator.get_aircraft_controllers().is_empty():
		return {
			"battle": battle,
			"squadron": squadron,
			"target": target,
		}
	var controller := coordinator.get_aircraft_controllers()[0]
	return {
		"battle": battle,
		"squadron": squadron,
		"target": target,
		"coordinator": coordinator,
		"controller": controller,
		"aircraft": controller.attack_state.get_aircraft(),
		"dive_data": dive_data,
		"desired_heading": desired_heading,
		"initial_heading": initial_heading,
		"target_instance_id": target.get_instance_id(),
		"initial_solution_revision": controller.attack_state.solution.revision,
	}


static func is_complete_fixture(fixture: Dictionary) -> bool:
	return fixture.has("controller") and fixture["controller"] != null \
		and fixture["aircraft"] != null


static func step(
		fixture: Dictionary,
		delta: float = DELTA,
		move_target: bool = true
) -> void:
	var target: ShipUnit = fixture.get("target") as ShipUnit
	if move_target and target != null and is_instance_valid(target):
		target.global_position += target.velocity * maxf(delta, 0.0)
	var coordinator: SquadronDiveBombCoordinator = fixture["coordinator"]
	coordinator.update(delta)
	var squadron: AircraftSquadron = fixture["squadron"]
	for aircraft_value in squadron.aircraft_units:
		var aircraft := aircraft_value as AircraftUnit
		if aircraft != null and aircraft.is_alive():
			aircraft.movement.update_movement(delta)
			aircraft.update_visual_bank(delta)


static func horizontal_heading(aircraft: AircraftUnit) -> Vector3:
	return AircraftSteeringMath.horizontal_heading(
		aircraft.get_world_velocity(),
		-aircraft.global_transform.basis.z
	)


static func run_until_dive(
		fixture: Dictionary,
		maximum_frames: int = 600,
		delta: float = DELTA
) -> Dictionary:
	var maximum_rate := 0.0
	var rate_sum := 0.0
	var rate_samples := 0
	var elapsed := 0.0
	var controller: AircraftDiveBombController = fixture["controller"]
	for frame in maximum_frames:
		step(fixture, delta)
		elapsed += delta
		if controller.attack_state.state \
				== DiveBombAircraftAttackState.State.ALIGNING:
			var rate := absf(
				controller.attack_state.current_turn_rate_degrees_sec
			)
			maximum_rate = maxf(maximum_rate, rate)
			if rate > 0.001:
				rate_sum += rate
				rate_samples += 1
		if controller.attack_state.state \
				== DiveBombAircraftAttackState.State.DIVING:
			return {
				"completed": true,
				"frames": frame + 1,
				"elapsed_sec": elapsed,
				"maximum_turn_rate_deg_sec": maximum_rate,
				"average_turn_rate_deg_sec": (
					rate_sum / float(rate_samples) if rate_samples > 0 else 0.0
				),
			}
		if controller.attack_state.state in [
			DiveBombAircraftAttackState.State.PULLING_OUT,
			DiveBombAircraftAttackState.State.FAILED,
			DiveBombAircraftAttackState.State.DESTROYED,
		]:
			break
	return {
		"completed": false,
		"frames": maximum_frames,
		"elapsed_sec": elapsed,
		"maximum_turn_rate_deg_sec": maximum_rate,
		"average_turn_rate_deg_sec": (
			rate_sum / float(rate_samples) if rate_samples > 0 else 0.0
		),
	}


static func finish(
		tree: SceneTree,
		fixture: Dictionary,
		test_name: String,
		failures: Array[String]
) -> void:
	var coordinator: SquadronDiveBombCoordinator = fixture.get("coordinator")
	if coordinator != null:
		coordinator.cancel(&"test_finished")
	var battle: BattleScene = fixture.get("battle") as BattleScene
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	await tree.process_frame
	await tree.process_frame
	for failure in failures:
		push_error("%s: %s" % [test_name, failure])
	print("%s %s" % [test_name, "PASS" if failures.is_empty() else "FAIL"])
	tree.quit(0 if failures.is_empty() else 1)


static func _find_enemy(battle: BattleScene) -> ShipUnit:
	for ship_value in battle.enemies:
		var ship := ship_value as ShipUnit
		if ship != null and is_instance_valid(ship):
			return ship
	return null
