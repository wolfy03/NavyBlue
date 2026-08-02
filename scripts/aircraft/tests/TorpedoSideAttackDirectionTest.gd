extends SceneTree

# Verifies TorpedoAttackPlanner.select_beam_direction produces a flank (beam)
# attack axis: perpendicular to the target's heading and on the side the
# squadron approaches from, flipping to the near beam as needed. Pure math.

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var heading := Vector3(0.0, 0.0, -1.0)

	var beam := TorpedoAttackPlanner.select_beam_direction(
		heading, Vector3(1.0, 0.0, 0.0)
	)
	_check(
		absf(beam.dot(heading)) < 0.001,
		"beam runs perpendicular to the target heading"
	)
	_check(
		beam.dot(Vector3(1.0, 0.0, 0.0)) > 0.0,
		"beam is on the squadron's approach side"
	)
	_check(beam.is_normalized(), "beam direction is normalized")

	var flipped := TorpedoAttackPlanner.select_beam_direction(
		heading, Vector3(-1.0, 0.0, 0.0)
	)
	_check(
		flipped.dot(Vector3(-1.0, 0.0, 0.0)) > 0.0,
		"beam flips to the near side when approaching from the other beam"
	)
	_check(
		absf(flipped.dot(heading)) < 0.001,
		"flipped beam stays perpendicular to the heading"
	)

	var degenerate := TorpedoAttackPlanner.select_beam_direction(
		Vector3.ZERO, Vector3(1.0, 0.0, 0.0)
	)
	_check(
		degenerate == Vector3.ZERO,
		"a degenerate heading yields no beam direction"
	)

	print(
		"TORPEDO_SIDE_ATTACK_DIRECTION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO SIDE ATTACK: %s" % label)
