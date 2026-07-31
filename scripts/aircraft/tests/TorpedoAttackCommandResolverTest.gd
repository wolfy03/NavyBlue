extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var squadron := AircraftSquadron.new()
	root.add_child(squadron)
	var profile := TorpedoAttackProfile.new()
	var environment := _create_environment(Vector2(4000.0, 4000.0))
	root.add_child(environment.battlefield_bounds)
	var resolver := TorpedoAttackCommandResolver.new()
	var short_result := resolver.resolve(
		squadron,
		Vector3.ZERO,
		Vector3(250.0, 0.0, 0.0),
		profile,
		environment
	)
	_check(short_result.success, "short drag resolves")
	_check(
		short_result.command.actual_run_distance_m + 0.01 >= 700.0,
		"short drag extends to minimum distance"
	)
	_check(
		short_result.command.attack_direction.is_equal_approx(Vector3.RIGHT),
		"short drag direction is preserved"
	)
	var long_result := resolver.resolve(
		squadron,
		Vector3.ZERO,
		Vector3(0.0, 0.0, -1200.0),
		profile,
		environment
	)
	_check(long_result.success, "long drag resolves")
	_check(
		is_equal_approx(long_result.command.actual_run_distance_m, 1200.0),
		"long drag distance is preserved"
	)
	_check(
		long_result.command.approach_point.is_equal_approx(
			Vector3(0.0, 0.0, 500.0)
		),
		"approach point is behind entry"
	)
	_check(
		long_result.command.escape_point.is_equal_approx(
			Vector3(0.0, 0.0, -1850.0)
		),
		"escape point continues beyond release"
	)
	var zero_result := resolver.resolve(
		squadron,
		Vector3.ZERO,
		Vector3.ZERO,
		profile,
		environment
	)
	_check(zero_result.success, "zero drag uses formation fallback")
	_check(
		zero_result.command.attack_direction.is_equal_approx(Vector3.FORWARD),
		"zero drag fallback follows formation"
	)
	var boundary_result := resolver.resolve(
		squadron,
		Vector3(1800.0, 0.0, 0.0),
		Vector3(2500.0, 0.0, 0.0),
		profile,
		environment
	)
	_check(boundary_result.success, "whole run translates inside battle area")
	_check(
		environment.battlefield_bounds.is_inside_bounds(
			boundary_result.command.escape_point
		),
		"translated escape point stays inside bounds"
	)
	var tiny_environment := _create_environment(Vector2(1000.0, 1000.0))
	root.add_child(tiny_environment.battlefield_bounds)
	var impossible := resolver.resolve(
		squadron,
		Vector3.ZERO,
		Vector3(700.0, 0.0, 0.0),
		profile,
		tiny_environment
	)
	_check(
		not impossible.success \
			and impossible.failure_reason == &"insufficient_attack_space",
		"insufficient battle space fails explicitly"
	)
	var offset_result := resolver.apply_lateral_offset(
		long_result.command,
		1.0,
		profile,
		environment
	)
	_check(offset_result.success, "multi-squadron offset resolves")
	_check(
		is_equal_approx(
			offset_result.command.actual_run_distance_m,
			long_result.command.actual_run_distance_m
		),
		"lateral offset preserves run distance"
	)
	squadron.queue_free()
	environment.battlefield_bounds.queue_free()
	tiny_environment.battlefield_bounds.queue_free()
	environment.free()
	tiny_environment.free()
	short_result = null
	long_result = null
	zero_result = null
	boundary_result = null
	impossible = null
	offset_result = null
	profile = null
	resolver = null
	environment = null
	tiny_environment = null
	await process_frame
	await process_frame
	if _failures.is_empty():
		print("TORPEDO_ATTACK_COMMAND_RESOLVER_TEST PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("TORPEDO RESOLVER TEST: %s" % failure)
		quit(1)


func _create_environment(map_size: Vector2) -> BattleEnvironment:
	var environment := BattleEnvironment.new()
	var bounds := BattlefieldBounds.new()
	var settings := BattlefieldSettings.new()
	settings.map_size_m = map_size
	bounds.settings = settings
	var rules := BattlefieldRules.new()
	rules.aircraft_command_margin_m = 0.0
	environment.setup(bounds, rules, null, 0.0)
	return environment


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
