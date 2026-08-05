extends SceneTree
## Friendly and neutral ships are never selected: an explicit friendly ship
## is rejected, and a radius full of friendlies falls back to the position.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var designation := Vector3.ZERO
	var friendly := DiveBombTargetingTestSupport.spawn_ship(
		root, &"ally", Vector3(40.0, 0.0, 0.0)
	)
	var neutral := DiveBombTargetingTestSupport.spawn_ship(
		root, &"neutral", Vector3(60.0, 0.0, 0.0)
	)
	var enemy := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(180.0, 0.0, 0.0)
	)
	var candidates := DiveBombTargetingTestSupport.ships(
		[friendly, neutral, enemy]
	)
	# Explicit friendly ship: rejected, the radius acquires the enemy instead.
	var explicit_request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0, &"player", friendly
	)
	var explicit_result := DiveBombTargetResolver.resolve(
		explicit_request,
		candidates
	)
	_check(
		explicit_result.get_ship() == enemy,
		"an explicit friendly ship is never selected"
	)
	# Mixed radius: the nearer friendly and neutral ships never outrank the
	# hostile one.
	var radius_request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0
	)
	var radius_result := DiveBombTargetResolver.resolve(
		radius_request,
		candidates
	)
	_check(
		radius_result.get_ship() == enemy,
		"radius acquisition ignores friendly and neutral ships"
	)
	# Friendlies only: position fallback.
	var fallback_result := DiveBombTargetResolver.resolve(
		radius_request,
		DiveBombTargetingTestSupport.ships([friendly, neutral])
	)
	_check(
		fallback_result.type \
			== DiveBombResolvedTarget.TargetType.WORLD_POSITION,
		"friendlies only falls back to the designated position"
	)
	friendly.queue_free()
	neutral.queue_free()
	enemy.queue_free()
	await process_frame
	print(
		"DIVE_BOMB_TARGET_RESOLVER_HOSTILE_ONLY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("HOSTILE ONLY: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
