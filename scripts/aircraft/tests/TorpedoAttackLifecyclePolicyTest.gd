extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var fixture := await _create_fixture()
	var squadron := fixture.squadron as AircraftSquadron
	if squadron == null:
		_report()
		return
	var controller := squadron.torpedo_attack_controller
	var movement := squadron.movement_controller
	var command := _make_command()
	movement.set_speed_override(&"other_system", 55.0)
	_check(controller.begin_attack(command), "attack begins")
	squadron.formation_center = Vector3(
		command.approach_point.x,
		squadron.squadron_data.aircraft_data.operating_altitude_m,
		command.approach_point.z
	)
	controller.update_attack(0.0)
	_check(
		controller.state == TorpedoAttackController.State.ALIGNING,
		"arrival enters ALIGNING"
	)
	_check(
		movement.has_speed_override(&"torpedo_attack") \
			and is_equal_approx(
				movement.get_speed_override(&"torpedo_attack"),
				controller.attack_profile.attack_run_speed_mps
			),
		"ALIGNING applies the named attack-run speed override"
	)
	controller.abort(&"test_abort", false)
	_check(
		not movement.has_speed_override(&"torpedo_attack"),
		"abort clears the torpedo speed override"
	)
	_check(
		movement.has_speed_override(&"other_system"),
		"abort preserves another owner's speed override"
	)
	_check(
		controller.get_finish_result() \
			== TorpedoAttackController.FinishResult.ABORTED_BEFORE_ATTACK,
		"an attack aborted before release is not reported as success"
	)

	_check(controller.begin_attack(command), "a second attack begins")
	squadron.formation_center = Vector3(
		command.approach_point.x,
		squadron.squadron_data.aircraft_data.operating_altitude_m,
		command.approach_point.z
	)
	controller.update_attack(0.0)
	controller.solution_refresher = Callable(self, "_return_null_solution")
	controller.command.solution_locked = false
	controller.state = TorpedoAttackController.State.ALIGNING
	var locked := controller._finalize_and_lock_solution()
	_check(not locked, "failed final refresh refuses the lock")
	_check(
		controller.command != null \
			and not controller.command.solution_locked,
		"the old solution remains unlocked after refresh failure"
	)
	_check(
		controller.state == TorpedoAttackController.State.ESCAPING,
		"failed final refresh transitions to escape"
	)
	_check(
		not movement.has_speed_override(&"torpedo_attack"),
		"refresh-failure escape clears the speed override"
	)
	controller.abort(&"cleanup", false)

	_check(controller.begin_attack(command), "a target-loss attack begins")
	squadron.formation_center = Vector3(
		command.approach_point.x,
		squadron.squadron_data.aircraft_data.operating_altitude_m,
		command.approach_point.z
	)
	controller.update_attack(0.0)
	controller.state = TorpedoAttackController.State.RELEASING
	controller.released_aircraft_count = 1
	var ammunition_before := squadron.get_alive_aircraft()[0] \
		.weapon_controller.get_remaining_ammunition()
	controller._handle_target_lost()
	_check(
		controller.state == TorpedoAttackController.State.ESCAPING,
		"target loss during RELEASING immediately starts escape"
	)
	_check(
		squadron.get_alive_aircraft()[0].weapon_controller \
			.get_remaining_ammunition() == ammunition_before,
		"target loss preserves payload that was not released"
	)
	controller.abort(&"target_lost_during_release", false)
	_check(
		controller.get_finish_result() \
			== TorpedoAttackController.FinishResult.PARTIAL_RELEASE,
		"a release already in progress reports a typed partial result"
	)
	controller.setup(squadron, movement, squadron.battle_services)
	_check(controller.begin_attack(command), "a shutdown-path attack begins")
	squadron.formation_center = Vector3(
		command.approach_point.x,
		squadron.squadron_data.aircraft_data.operating_altitude_m,
		command.approach_point.z
	)
	controller.update_attack(0.0)
	controller.shutdown()
	_check(
		not movement.has_speed_override(&"torpedo_attack") \
			and movement.has_speed_override(&"other_system"),
		"shutdown clears only the torpedo-owned speed override"
	)
	await _cleanup_fixture(fixture)
	_report()


func _return_null_solution() -> TorpedoAttackCommand:
	return null


func _make_command() -> TorpedoAttackCommand:
	var command := TorpedoAttackCommand.new()
	command.command_id = 301
	command.approach_point = Vector3(0.0, 0.0, 1000.0)
	command.entry_point = Vector3(0.0, 0.0, 500.0)
	command.actual_release_point = Vector3(0.0, 0.0, -200.0)
	command.requested_release_point = command.actual_release_point
	command.escape_point = Vector3(0.0, 0.0, -850.0)
	command.attack_direction = Vector3.FORWARD
	command.minimum_run_distance_m = 700.0
	command.actual_run_distance_m = 700.0
	return command


func _create_fixture() -> Dictionary:
	var services := BattleTestServices.create(self)
	var carrier := load("res://scenes/unit/ship.tscn").instantiate() as ShipUnit
	carrier.team = FactionRelations.PLAYER
	carrier.player_controlled = true
	root.add_child(carrier)
	var aircraft_root := Node3D.new()
	aircraft_root.add_to_group(&"aircraft_root")
	root.add_child(aircraft_root)
	var squadron := load(
		"res://scenes/aircraft/aircraft_squadron.tscn"
	).instantiate() as AircraftSquadron
	root.add_child(squadron)
	var data := load(
		"res://resources/aircraft/squadrons/basic_torpedo_squadron.tres"
	) as SquadronData
	squadron.setup(carrier, data, aircraft_root, 1, services)
	squadron.launch_to(Vector3(0.0, 180.0, 500.0))
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	return {
		"squadron": squadron,
		"carrier": carrier,
		"aircraft_root": aircraft_root,
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var squadron := fixture.squadron as AircraftSquadron
	if squadron != null:
		squadron.shutdown()
		squadron.queue_free()
	for key in [&"aircraft_root", &"carrier"]:
		var node := fixture.get(key) as Node
		if node != null:
			node.queue_free()
	await process_frame
	await process_frame


func _report() -> void:
	print(
		"TORPEDO_ATTACK_LIFECYCLE_POLICY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO LIFECYCLE POLICY: %s" % label)
