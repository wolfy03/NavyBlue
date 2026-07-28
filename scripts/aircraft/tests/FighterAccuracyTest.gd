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
		FighterTestSupport.FIGHTER_DATA,
		FactionRelations.ENEMY,
		Vector3(0.0, 0.0, -300.0)
	)
	var base := attacker.get_fighter_combat_data()
	var gun := attacker.weapon_controller.weapon_data.gun_data
	var optimal := FighterCombatResolver.calculate_hit_probability(
		attacker, target, base, gun
	)
	target.global_position = Vector3(0.0, 0.0, -680.0)
	var distant := FighterCombatResolver.calculate_hit_probability(
		attacker, target, base, gun
	)
	_check(
		optimal.range_factor > distant.range_factor \
			and optimal.hit_probability > distant.hit_probability,
		"optimal range is more accurate than maximum range"
	)

	target.global_position = Vector3(0.0, 0.0, -300.0)
	var low_pilot := base.duplicate(true) as FighterCombatData
	low_pilot.pilot_skill = 0.0
	var high_pilot := base.duplicate(true) as FighterCombatData
	high_pilot.pilot_skill = 1.0
	_check(
		_probability(attacker, target, high_pilot, gun) \
			> _probability(attacker, target, low_pilot, gun),
		"pilot skill improves accuracy"
	)

	target.global_position = Vector3(
		sin(deg_to_rad(25.0)) * 300.0,
		0.0,
		-cos(deg_to_rad(25.0)) * 300.0
	)
	var low_tracking := base.duplicate(true) as FighterCombatData
	low_tracking.tracking_skill = 0.0
	var high_tracking := base.duplicate(true) as FighterCombatData
	high_tracking.tracking_skill = 1.0
	_check(
		_probability(attacker, target, high_tracking, gun) \
			> _probability(attacker, target, low_tracking, gun),
		"tracking skill improves edge-of-cone accuracy"
	)

	target.global_position = Vector3(0.0, 0.0, -300.0)
	var target_combat := target.aircraft_data.fighter_combat_data
	var original_evasion := target_combat.evasion_skill
	target_combat.evasion_skill = 0.0
	var low_evasion := _probability(attacker, target, base, gun)
	target_combat.evasion_skill = 1.0
	var high_evasion := _probability(attacker, target, base, gun)
	target_combat.evasion_skill = original_evasion
	_check(high_evasion < low_evasion, "target evasion lowers accuracy")

	attacker.velocity = Vector3.ZERO
	target.velocity = Vector3.ZERO
	var slow := _probability(attacker, target, base, gun)
	target.velocity = Vector3(500.0, 0.0, 0.0)
	var fast := _probability(attacker, target, base, gun)
	_check(fast < slow, "relative speed lowers accuracy")
	_check(
		optimal.hit_probability >= base.minimum_accuracy \
			and optimal.hit_probability <= base.maximum_accuracy,
		"probability respects configured limits"
	)
	arena.queue_free()
	await process_frame
	_finish()


func _probability(
		attacker: AircraftUnit,
		target: AircraftUnit,
		data: FighterCombatData,
		gun: AircraftGunData
) -> float:
	return FighterCombatResolver.calculate_hit_probability(
		attacker, target, data, gun
	).hit_probability


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("FIGHTER ACCURACY TEST: %s" % failure)
	print(
		"FIGHTER_ACCURACY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)
