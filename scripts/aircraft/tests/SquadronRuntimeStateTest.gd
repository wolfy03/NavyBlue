extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var state := SquadronRuntimeState.new()
	state.squadron_id = "test"
	state.total_aircraft = 4
	state.available_aircraft = 4
	state.active_aircraft = 3
	state.lost_aircraft = 2
	state.rearm_time_left = -2.0
	state.normalize()
	_check(
		state.available_aircraft + state.active_aircraft \
			+ state.lost_aircraft <= state.total_aircraft,
		"normalize preserves the aircraft-count invariant"
	)
	_check(state.rearm_time_left == 0.0, "negative rearm time is clamped")
	var restored := SquadronRuntimeState.from_dictionary(
		state.to_dictionary()
	)
	_check(restored.squadron_id == "test", "squadron id round-trips")
	_check(
		restored.to_dictionary() == state.to_dictionary(),
		"runtime state round-trips through save data"
	)
	for failure in _failures:
		push_error("SQUADRON RUNTIME STATE TEST: %s" % failure)
	print(
		"SQUADRON_RUNTIME_STATE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
