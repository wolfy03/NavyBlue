extends RefCounted
class_name BallisticSolution

var success := false
var launch_direction := Vector3.ZERO
var launch_velocity := Vector3.ZERO
var elevation_rad := 0.0
var estimated_flight_time_sec := 0.0
var predicted_impact_position := Vector3.ZERO
var horizontal_distance_m := 0.0
var failure_reason: StringName = &""


static func failed(reason: StringName) -> BallisticSolution:
	var result := BallisticSolution.new()
	result.failure_reason = reason
	return result
