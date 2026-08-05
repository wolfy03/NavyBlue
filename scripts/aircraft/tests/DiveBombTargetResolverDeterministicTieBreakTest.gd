extends SceneTree
## Equidistant hostile ships are tie-broken deterministically (authored ship
## id, then stable combat identity): allocation and candidate order do not
## influence the winner.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var designation := Vector3.ZERO
	var first := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(120.0, 0.0, 0.0)
	)
	var second := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(-120.0, 0.0, 0.0)
	)
	first.combat_spawn_id = CombatIdentity.for_stage_spawn(
		&"tie_break_test", &"enemy", 0
	)
	second.combat_spawn_id = CombatIdentity.for_stage_spawn(
		&"tie_break_test", &"enemy", 1
	)
	var request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0
	)
	var forward := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([first, second])
	)
	var reversed_order := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([second, first])
	)
	_check(
		forward.get_ship() != null \
			and forward.get_ship() == reversed_order.get_ship(),
		"candidate order never changes the tie-break winner"
	)
	var expected := first \
		if CombatIdentity.for_ship(first) < CombatIdentity.for_ship(second) \
		else second
	_check(
		forward.get_ship() == expected,
		"equal ship ids tie-break on stable combat identity"
	)
	for _round in 8:
		var repeat := DiveBombTargetResolver.resolve(
			request,
			DiveBombTargetingTestSupport.ships([first, second])
		)
		if repeat.get_ship() != expected:
			_check(false, "repeated resolves always pick the same ship")
			break
	first.queue_free()
	second.queue_free()
	await process_frame
	print(
		"DIVE_BOMB_TARGET_RESOLVER_DETERMINISTIC_TIE_BREAK_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("TIE BREAK: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
