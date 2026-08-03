extends RefCounted
class_name GunneryAccuracyResult

var success := false
var failure_reason: StringName = &""

var ideal_aim_point := Vector3.ZERO
var actual_aim_point := Vector3.ZERO

var salvo_bias_offset := Vector3.ZERO
var shell_dispersion_offset := Vector3.ZERO

var range_error_m := 0.0
var lateral_error_m := 0.0
var shell_range_dispersion_m := 0.0
var shell_lateral_dispersion_m := 0.0

var range_sigma_m := 0.0
var lateral_sigma_m := 0.0
var shell_dispersion_sigma_m := 0.0


static func failed(reason: StringName) -> GunneryAccuracyResult:
	var result := GunneryAccuracyResult.new()
	result.failure_reason = reason
	return result
