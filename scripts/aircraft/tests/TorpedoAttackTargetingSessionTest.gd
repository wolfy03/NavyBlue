extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var environment := BattleEnvironment.new()
	var bounds := BattlefieldBounds.new()
	var bounds_settings := BattlefieldSettings.new()
	bounds_settings.map_size_m = Vector2(6000.0, 6000.0)
	bounds.settings = bounds_settings
	root.add_child(bounds)
	environment.setup(bounds, BattlefieldRules.new(), null, 0.0)
	var session := TorpedoAttackTargetingSession.new()
	root.add_child(session)
	session.setup(WorldPointerResolver.new(), environment)
	var carrier_scene := load("res://scenes/unit/ship.tscn") as PackedScene
	var carrier := carrier_scene.instantiate() as ShipUnit
	carrier.team = FactionRelations.PLAYER
	carrier.player_controlled = true
	root.add_child(carrier)
	var aircraft_parent := Node3D.new()
	root.add_child(aircraft_parent)
	var squadron_scene := load(
		"res://scenes/aircraft/aircraft_squadron.tscn"
	) as PackedScene
	var squadron := squadron_scene.instantiate() as AircraftSquadron
	root.add_child(squadron)
	var squadron_data := load(
		"res://resources/aircraft/squadrons/basic_torpedo_squadron.tres"
	) as SquadronData
	squadron.setup(carrier, squadron_data, aircraft_parent, 1)
	squadron.launch_to(Vector3.ZERO)
	squadron.set_command_authority(AircraftSquadron.CommandAuthority.PLAYER)
	var squadrons: Array[AircraftSquadron] = [squadron]
	_check(
		session.begin(squadrons, Vector3.ZERO),
		"torpedo squadron starts targeting"
	)
	_check(
		session.state == TorpedoAttackTargetingSession.State.ARMED,
		"session starts armed"
	)
	session.begin_drag(Vector3.ZERO)
	session.update_drag(Vector3(250.0, 0.0, 0.0))
	var preview := session.get_current_preview()
	_check(preview != null and preview.valid, "short drag preview is valid")
	_check(
		preview != null and preview.displayed_distance_m + 0.01 >= 700.0,
		"preview displays corrected minimum distance"
	)
	var commands := session.complete_drag(Vector3(250.0, 0.0, 0.0))
	_check(commands.size() == 1, "completion creates one typed command")
	_check(
		commands.size() == 1 \
			and commands[0].requested_run_distance_m < 700.0 \
			and commands[0].actual_run_distance_m + 0.01 >= 700.0,
		"completed command preserves requested and corrected distances"
	)
	_check(not session.is_active(), "completion deactivates session")
	_check(
		session.begin(squadrons, Vector3.ZERO),
		"session can start again after completion"
	)
	session.cancel(&"test_cancel")
	_check(not session.is_active(), "cancel deactivates session")
	_check(
		session.get_active_squadrons().is_empty(),
		"cancel clears squadron references"
	)
	session.shutdown()
	squadron.shutdown()
	root.remove_child(session)
	session.free()
	squadron.queue_free()
	aircraft_parent.queue_free()
	carrier.queue_free()
	root.remove_child(bounds)
	bounds.free()
	environment.free()
	commands.clear()
	preview = null
	squadrons.clear()
	session = null
	squadron = null
	squadron_data = null
	squadron_scene = null
	carrier = null
	carrier_scene = null
	aircraft_parent = null
	bounds = null
	bounds_settings = null
	environment = null
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	print(
		"TORPEDO_ATTACK_TARGETING_SESSION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO TARGETING: %s" % label)
