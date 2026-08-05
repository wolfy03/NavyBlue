extends SceneTree
## With the position fallback forbidden, an order that acquires nothing
## resolves to INVALID instead of a position target.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var request := DiveBombTargetingTestSupport.make_request(
		Vector3.ZERO, 250.0, &"player", null, false
	)
	var empty := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([])
	)
	_check(
		empty.type == DiveBombResolvedTarget.TargetType.INVALID,
		"no target with fallback forbidden resolves to INVALID"
	)
	_check(
		not empty.is_valid(),
		"the INVALID result reports itself as not valid"
	)
	# A hostile ship in the radius still resolves normally.
	var enemy := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(100.0, 0.0, 0.0)
	)
	var acquired := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([enemy])
	)
	_check(
		acquired.get_ship() == enemy,
		"forbidding the fallback never blocks ship acquisition"
	)
	enemy.queue_free()
	await process_frame
	print(
		"DIVE_BOMB_TARGET_RESOLVER_NO_FALLBACK_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("NO FALLBACK: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
