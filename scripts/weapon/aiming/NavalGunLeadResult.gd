extends RefCounted
class_name NavalGunLeadResult

var success := false

var launch_position := Vector3.ZERO
var target_current_position := Vector3.ZERO
var target_velocity := Vector3.ZERO

var predicted_impact_position := Vector3.ZERO

var projectile_flight_time_sec := 0.0
var horizontal_distance_m := 0.0
var projectile_speed_mps := 0.0
var elevation_rad := 0.0

var failure_reason: StringName = &""


static func failed(reason: StringName) -> NavalGunLeadResult:
	var result := NavalGunLeadResult.new()
	result.failure_reason = reason
	return result
