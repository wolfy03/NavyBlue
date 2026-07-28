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
	var target := FighterTestSupport.spawn_aircraft(
		arena,
		FighterTestSupport.BOMBER_DATA,
		FactionRelations.ENEMY,
		Vector3(0.0, 0.0, -300.0)
	)
	var fighter_data := attacker.get_fighter_combat_data()
	var gun := attacker.weapon_controller.weapon_data.gun_data
	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 7341
	var first := FighterCombatResolver.resolve_burst(
		attacker, target, fighter_data, gun, 40, first_rng
	)
	var second_rng := RandomNumberGenerator.new()
	second_rng.seed = 7341
	var second := FighterCombatResolver.resolve_burst(
		attacker, target, fighter_data, gun, 40, second_rng
	)
	_check(
		first.valid \
			and first.hit_count == second.hit_count \
			and is_equal_approx(
				first.hit_probability,
				second.hit_probability
			),
		"fixed RNG seed reproduces burst result"
	)
	var initial_ammo := attacker.weapon_controller.get_remaining_ammunition()
	var consumed := attacker.weapon_controller.consume_gun_rounds(8)
	_check(
		consumed == 8 \
			and attacker.weapon_controller.get_remaining_ammunition() \
				== initial_ammo - 8,
		"burst consumes exact ammunition"
	)
	var remaining := attacker.weapon_controller.get_remaining_ammunition()
	var final_consumed := attacker.weapon_controller.consume_gun_rounds(
		remaining + 100
	)
	_check(
		final_consumed == remaining \
			and not attacker.weapon_controller.has_ammunition() \
			and not attacker.weapon_controller.can_fire_gun_burst(),
		"gun never consumes beyond remaining ammunition"
	)
	arena.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("FIGHTER BURST RESOLUTION TEST: %s" % failure)
	print(
		"FIGHTER_BURST_RESOLUTION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)
