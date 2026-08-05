extends SceneTree
## An explicitly designated valid hostile ship is always selected, even when
## it sits outside the acquisition radius and a nearer hostile ship exists.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var designation := Vector3.ZERO
	var near_enemy := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(50.0, 0.0, 0.0)
	)
	var far_explicit := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(1200.0, 0.0, 0.0)
	)
	var request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0, &"player", far_explicit
	)
	var result := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([near_enemy, far_explicit])
	)
	_check(
		result.type == DiveBombResolvedTarget.TargetType.SHIP,
		"explicit hostile ship resolves to a ship target"
	)
	_check(
		result.get_ship() == far_explicit,
		"the explicit ship wins even outside the radius"
	)
	_check(
		result.resolution_reason == &"explicit_target",
		"resolution reason records the explicit selection"
	)
	near_enemy.queue_free()
	far_explicit.queue_free()
	await process_frame
	print(
		"DIVE_BOMB_TARGET_RESOLVER_EXPLICIT_SHIP_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("EXPLICIT SHIP: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
