extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
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
	var aircraft := squadron.get_alive_aircraft()[0]
	aircraft.activate()
	aircraft.set_physics_process(false)
	aircraft.global_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 25.0, 0.0)
	)
	aircraft.velocity = Vector3(0.0, 0.0, -65.0)
	var command := TorpedoAttackCommand.new()
	command.actual_release_point = Vector3.ZERO
	command.entry_point = Vector3(0.0, 0.0, 700.0)
	command.escape_point = Vector3(0.0, 0.0, -650.0)
	command.attack_direction = Vector3.FORWARD
	command.command_plane_height_m = 0.0
	var service := AircraftTorpedoReleaseService.new()
	var evaluator := TorpedoAttackFlightEvaluator.new()
	var resolved := {}
	aircraft.weapon_controller.disable_weapon_release()
	var first := service.release_ready_aircraft(
		squadron,
		command,
		squadron.get_torpedo_attack_profile(),
		evaluator,
		resolved
	)
	_check(
		first.failures.size() == 1 \
			and first.failures[0].retryable \
			and first.resolved_aircraft_ids.is_empty(),
		"a transient creation path failure remains retryable"
	)
	service.release_ready_aircraft(
		squadron, command, squadron.get_torpedo_attack_profile(), evaluator, resolved
	)
	var exhausted := service.release_ready_aircraft(
		squadron, command, squadron.get_torpedo_attack_profile(), evaluator, resolved
	)
	_check(
		exhausted.failures.size() == 1 \
			and not exhausted.failures[0].retryable \
			and aircraft.get_instance_id() in exhausted.resolved_aircraft_ids,
		"a transient failure becomes resolved after the configured retries"
	)
	_check(
		aircraft.weapon_controller.get_remaining_ammunition() == 1,
		"failed release attempts preserve payload"
	)
	squadron.shutdown()
	squadron.queue_free()
	aircraft_root.queue_free()
	carrier.queue_free()
	await process_frame
	await process_frame
	print(
		"TORPEDO_RELEASE_SERVICE_POLICY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO RELEASE SERVICE POLICY: %s" % label)
