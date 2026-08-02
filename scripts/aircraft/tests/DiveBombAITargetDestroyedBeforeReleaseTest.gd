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
	var target := load("res://scenes/unit/ship.tscn").instantiate() as ShipUnit
	target.team = FactionRelations.ENEMY
	root.add_child(target)
	var aircraft_root := Node3D.new()
	aircraft_root.add_to_group(&"aircraft_root")
	root.add_child(aircraft_root)
	var squadron := load(
		"res://scenes/aircraft/aircraft_squadron.tscn"
	).instantiate() as AircraftSquadron
	root.add_child(squadron)
	var data := load(
		"res://resources/aircraft/squadrons/basic_bomber_squadron.tres"
	) as SquadronData
	squadron.setup(carrier, data, aircraft_root, 1, services)
	squadron.launch_to(Vector3(0.0, 180.0, 500.0))
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	var controller := squadron.dive_bomb_controller
	var begin_result := controller.begin_dive_with_source(
		target.global_position,
		Vector3.ZERO,
		AircraftSquadron.DiveControlSource.AI
	)
	_check(
		begin_result == DiveBombAttackController.BeginDiveResult.STARTED,
		"AI dive begins"
	)
	var aircraft := squadron.get_alive_aircraft()[0]
	var ammunition_before := aircraft.weapon_controller \
		.get_remaining_ammunition()
	var behavior := DiveBombMissionBehavior.new()
	behavior.owner_squadron = squadron
	behavior.state = DiveBombMissionBehavior.State.DIVING
	behavior._finished = false
	behavior._target_ref = weakref(target)
	target._is_sinking = true
	behavior.update(0.0)
	_check(
		controller.state == DiveBombAttackController.State.PULLING_OUT,
		"target loss before release starts pull-out"
	)
	_check(
		aircraft.weapon_controller.get_remaining_ammunition() \
			== ammunition_before,
		"target-loss pull-out preserves unreleased payload"
	)
	squadron.shutdown()
	squadron.queue_free()
	aircraft_root.queue_free()
	target.queue_free()
	carrier.queue_free()
	await process_frame
	await process_frame
	print(
		"DIVE_BOMB_AI_TARGET_DESTROYED_BEFORE_RELEASE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("DIVE TARGET LOSS: %s" % label)
