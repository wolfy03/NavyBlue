extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var attacker := FighterTestSupport.spawn_aircraft(
		arena,
		FighterTestSupport.FIGHTER_DATA,
		FactionRelations.PLAYER,
		Vector3.ZERO
	)
	_check(_inside(attacker, 0.0), "forward target is inside cone")
	_check(_inside(attacker, 30.0), "+30 degree boundary is inside")
	_check(_inside(attacker, -30.0), "-30 degree boundary is inside")
	_check(not _inside(attacker, 30.2), "outside right boundary is rejected")
	_check(not _inside(attacker, -30.2), "outside left boundary is rejected")
	_check(not _inside(attacker, 180.0), "rear target is rejected")
	arena.queue_free()
	await process_frame
	_finish()


func _inside(attacker: AircraftUnit, degrees: float) -> bool:
	var radians := deg_to_rad(degrees)
	var position := Vector3(
		sin(radians) * 300.0,
		0.0,
		-cos(radians) * 300.0
	)
	return FighterCombatResolver.is_inside_firing_cone(
		attacker,
		position,
		60.0
	)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("FIGHTER FIRING CONE TEST: %s" % failure)
	print(
		"FIGHTER_FIRING_CONE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)
