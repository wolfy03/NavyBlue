extends SceneTree

# Verifies §12: when a release cannot be resolved (here, the attack run cannot
# fit inside a tiny battle area), the targeting session does NOT cancel. It ends
# the drag and returns to ARMED so the player can immediately drag again.

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var environment := BattleEnvironment.new()
	var bounds := BattlefieldBounds.new()
	var bounds_settings := BattlefieldSettings.new()
	# Deliberately smaller than one attack run so any release fails to fit.
	bounds_settings.map_size_m = Vector2(1000.0, 1000.0)
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

	_check(session.begin(squadrons, Vector3.ZERO), "targeting starts")
	session.begin_drag(Vector3.ZERO)
	var commands := session.resolve_drag_commands(Vector3(700.0, 0.0, 0.0))
	_check(commands.is_empty(), "failed resolve yields no commands")
	_check(
		session.state == TorpedoAttackTargetingSession.State.ARMED,
		"failed release returns the session to ARMED"
	)
	_check(session.is_active(), "session stays active after a failed release")
	var preview := session.get_current_preview()
	_check(
		preview != null and not preview.valid,
		"an invalid preview is shown after the failed release"
	)
	# The player can drag again from ARMED.
	session.begin_drag(Vector3.ZERO)
	_check(
		session.state == TorpedoAttackTargetingSession.State.DRAGGING,
		"player can start a new drag after the failure"
	)

	session.cancel(&"test_cancel")
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
	print(
		"TORPEDO_RESOLVE_FAILURE_RETURNS_TO_ARMED_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO ARMED RETURN: %s" % label)
