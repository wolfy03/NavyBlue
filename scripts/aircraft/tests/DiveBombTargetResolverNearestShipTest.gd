extends SceneTree
## With several hostile ships inside the radius, the one closest to the
## designated position is acquired.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	var designation := Vector3(0.0, 0.0, 0.0)
	var far := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(200.0, 0.0, 0.0)
	)
	var nearest := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(0.0, 0.0, 80.0)
	)
	var middle := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(-140.0, 0.0, 0.0)
	)
	var request := DiveBombTargetingTestSupport.make_request(
		designation, 250.0
	)
	var result := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([far, nearest, middle])
	)
	_check(
		result.get_ship() == nearest,
		"the ship closest to the designation is acquired"
	)
	_check(
		result.resolution_reason == &"radius_acquired",
		"resolution reason records the radius acquisition"
	)
	_check(
		absf(result.distance_from_designation_m - 80.0) < 1.0,
		"the designation distance is measured on the XZ plane"
	)
	# Vertical separation is ignored: a high designation still acquires.
	request.designated_world_position = Vector3(0.0, 300.0, 0.0)
	var elevated := DiveBombTargetResolver.resolve(
		request,
		DiveBombTargetingTestSupport.ships([far, nearest, middle])
	)
	_check(
		elevated.get_ship() == nearest,
		"the Y distance never affects acquisition"
	)
	far.queue_free()
	nearest.queue_free()
	middle.queue_free()
	await process_frame
	print(
		"DIVE_BOMB_TARGET_RESOLVER_NEAREST_SHIP_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	for failure in _failures:
		push_error("NEAREST SHIP: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
