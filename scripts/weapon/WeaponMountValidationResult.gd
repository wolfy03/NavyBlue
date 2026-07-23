extends RefCounted
class_name WeaponMountValidationResult

var valid := false
var reason := ""


func setup(is_valid: bool, validation_reason: String = "") -> WeaponMountValidationResult:
	valid = is_valid
	reason = validation_reason
	return self
