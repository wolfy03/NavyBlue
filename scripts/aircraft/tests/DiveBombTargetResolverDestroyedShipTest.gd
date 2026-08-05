extends SceneTree
## Destroyed or sinking ships are never selected — not as explicit targets
## and not by radius acquisition.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var designation := Vector3.ZERO
	var sinking := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(50.0, 0.0, 0.0)
	)
	var alive := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(200.0, 0.0, 0.0)
	)
	sinking._is_sinking = true
	# Explicit dead ship: rejected, radius acquires the surviving ship.
	var explicit_request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0, &"player", sinking
	)
	var explicit_result := DiveBombTargetResolver.resolve(
		explicit_request,
		DiveBombTargetingTestSupport.ships([sinking, alive])
	)
	_check(
		explicit_result.get_ship() == alive,
		"an explicit destroyed ship is never selected"
	)
	# Radius acquisition skips the nearer sinking ship.
	var radius_request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0
	)
	var radius_result := DiveBombTargetResolver.resolve(
		radius_request,
		DiveBombTargetingTestSupport.ships([sinking, alive])
	)
	_check(
		radius_result.get_ship() == alive,
		"radius acquisition skips destroyed ships"
	)
	# Only the destroyed ship exists: position fallback.
	var fallback := DiveBombTargetResolver.resolve(
		radius_request,
		DiveBombTargetingTestSupport.ships([sinking])
	)
	_check(
		fallback.type == DiveBombResolvedTarget.TargetType.WORLD_POSITION,
		"a dead-only candidate list falls back to the position"
	)
	sinking.queue_free()
	alive.queue_free()
	await process_frame
	print(
		"DIVE_BOMB_TARGET_RESOLVER_DESTROYED_SHIP_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("DESTROYED SHIP: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
