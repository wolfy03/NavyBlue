extends SceneTree
## The position fallback: no candidates at all yields the designated world
## position as a fixed target with zero velocity.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var designation := Vector3(500.0, 0.0, -750.0)
	var request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0
	)
	var result := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([])
	)
	_check(
		result.type == DiveBombResolvedTarget.TargetType.WORLD_POSITION,
		"no candidates falls back to the position"
	)
	_check(
		result.designated_world_position == designation \
			and result.resolved_aim_position == designation,
		"the fallback aims at the designated position itself"
	)
	_check(
		result.target_velocity == Vector3.ZERO \
			and result.get_target_velocity() == Vector3.ZERO,
		"the fallback target velocity is zero"
	)
	_check(
		result.resolution_reason == &"position_fallback",
		"resolution reason records the fallback"
	)
	_check(
		result.get_aim_position() == designation,
		"the aim position accessor returns the designation"
	)
	print(
		"DIVE_BOMB_TARGET_RESOLVER_POSITION_FALLBACK_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("POSITION FALLBACK: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
