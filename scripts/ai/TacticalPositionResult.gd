extends RefCounted
class_name TacticalPositionResult

var position: Vector3 = Vector3.ZERO
var heading: Vector3 = Vector3.FORWARD
var valid := false
var was_clamped := false
var side_sign := 1.0
var requires_side_switch := false
var reason: StringName = &""
var clamp_distance_m := 0.0


func setup(
		next_position: Vector3,
		next_heading: Vector3,
		is_valid: bool,
		clamped: bool,
		next_side_sign: float,
		result_reason: StringName,
		clamp_distance: float = 0.0
) -> TacticalPositionResult:
	position = next_position
	heading = next_heading.normalized() if next_heading.length_squared() > 0.01 else Vector3.FORWARD
	valid = is_valid
	was_clamped = clamped
	side_sign = -1.0 if next_side_sign < 0.0 else 1.0
	reason = result_reason
	clamp_distance_m = maxf(clamp_distance, 0.0)
	return self
