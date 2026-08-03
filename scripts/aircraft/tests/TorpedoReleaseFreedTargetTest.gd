extends SceneTree
## Regression: a torpedo run is intentionally never aborted once it reaches
## RELEASING, so the tracked target can sink while the drop is still pending.
## Propagating that freed reference into the typed launch request raised
## "Invalid assignment of property 'target_ship' ... of type 'previously
## freed'" on every release frame.
##
## Note on the assertions: the engine error does not stop execution, so the
## _check calls below pass with or without the guard. The regression signal is
## a stderr free of "previously freed" while this case runs.

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
	# A --script run has no current_scene, so the weapon controller needs an
	# explicit projectile root or every release reports spawn_failed.
	var projectile_root := Node3D.new()
	projectile_root.add_to_group(&"projectile_root")
	root.add_child(projectile_root)
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

	var victim := load("res://scenes/unit/ship.tscn").instantiate() as ShipUnit
	victim.team = FactionRelations.ENEMY
	root.add_child(victim)
	victim.global_position = Vector3(0.0, 0.0, -650.0)
	await physics_frame

	var command := TorpedoAttackCommand.new()
	command.actual_release_point = Vector3.ZERO
	command.entry_point = Vector3(0.0, 0.0, 700.0)
	command.escape_point = Vector3(0.0, 0.0, -650.0)
	command.attack_direction = Vector3.FORWARD
	command.command_plane_height_m = 0.0
	command.target_ship = victim
	_check(
		command.get_live_target_ship() == victim,
		"a live target is returned unchanged"
	)

	# The target sinks mid-run: free it without clearing the command.
	victim.free()
	_check(
		command.get_live_target_ship() == null,
		"a freed target resolves to null instead of a stale reference"
	)
	_check(
		command.target_ship == null,
		"the stale reference is cleared from the command"
	)
	var copy := command.duplicate_command()
	_check(
		copy.target_ship == null,
		"duplicate_command does not propagate a freed target"
	)

	var service := AircraftTorpedoReleaseService.new()
	var evaluator := TorpedoAttackFlightEvaluator.new()
	var result := service.release_ready_aircraft(
		squadron,
		command,
		squadron.get_torpedo_attack_profile(),
		evaluator,
		{}
	)
	_check(
		result.attempted > 0,
		"the committed drop still runs after its target sinks"
	)
	_check(
		result.released > 0 and result.failed == 0,
		"the release succeeds with no tracked target ship (released=%d failed=%d reasons=%s)"
			% [result.released, result.failed, result.failure_reasons]
	)

	squadron.shutdown()
	squadron.queue_free()
	aircraft_root.queue_free()
	projectile_root.queue_free()
	carrier.queue_free()
	await process_frame
	await process_frame
	print(
		"TORPEDO_RELEASE_FREED_TARGET_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO RELEASE FREED TARGET: %s" % label)
