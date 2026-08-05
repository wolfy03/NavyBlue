extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var first := ShipUnit.new()
	var noise := Node.new()
	var second := ShipUnit.new()
	first.ship_id = "dd_bluewind"
	first.name = "Bluewind_1"
	first.team = &"player"
	first.combat_spawn_id = CombatIdentity.for_stage_spawn(
		&"identity_test", &"player", 0
	)
	second.ship_id = "dd_bluewind"
	second.name = "Bluewind_1"
	second.team = &"player"
	second.combat_spawn_id = first.combat_spawn_id
	_check(
		first.get_instance_id() != second.get_instance_id(),
		"fixture uses different runtime ids"
	)
	_check(
		CombatIdentity.for_ship(first) == CombatIdentity.for_ship(second),
		"equivalent authored ships have the same combat id"
	)
	var seed_a := GunneryAccuracyResolver.make_salvo_seed(
		CombatIdentity.for_ship(first),
		12345,
		2,
		4,
		&"main"
	)
	var seed_b := GunneryAccuracyResolver.make_salvo_seed(
		CombatIdentity.for_ship(second),
		12345,
		2,
		4,
		&"main"
	)
	_check(seed_a == seed_b, "gunnery seed ignores allocation order")
	first.free()
	noise.free()
	second.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	print("COMBAT_IDENTITY_DETERMINISM_TEST failures=%d" % _failures.size())
	for failure in _failures:
		push_error("COMBAT ID: %s" % failure)
	quit(0 if _failures.is_empty() else 1)
