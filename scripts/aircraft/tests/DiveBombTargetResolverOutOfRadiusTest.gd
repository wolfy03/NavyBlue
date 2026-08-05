extends SceneTree
## Hostile ships outside the acquisition radius are not acquired: the order
## falls back to the designated position.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var designation := Vector3.ZERO
	var outside := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(400.0, 0.0, 0.0)
	)
	var request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0
	)
	var result := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([outside])
	)
	_check(
		result.type == DiveBombResolvedTarget.TargetType.WORLD_POSITION,
		"a ship outside the radius is not acquired"
	)
	# Exactly on the boundary: inside.
	outside.global_position = Vector3(250.0, 0.0, 0.0)
	var boundary := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([outside])
	)
	_check(
		boundary.get_ship() == outside,
		"a ship exactly on the radius boundary is acquired"
	)
	# Radius zero disables acquisition entirely.
	request.acquisition_radius_m = 0.0
	outside.global_position = Vector3(1.0, 0.0, 0.0)
	var disabled := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([outside])
	)
	_check(
		disabled.type == DiveBombResolvedTarget.TargetType.WORLD_POSITION,
		"radius zero disables auto-acquisition"
	)
	outside.queue_free()
	await process_frame
	print(
		"DIVE_BOMB_TARGET_RESOLVER_OUT_OF_RADIUS_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("OUT OF RADIUS: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
