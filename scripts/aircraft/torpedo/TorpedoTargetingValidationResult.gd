extends RefCounted
class_name TorpedoTargetingValidationResult

var valid := false
var failure_reason: StringName
var profile: TorpedoAttackProfile


static func accepted(
		attack_profile: TorpedoAttackProfile
) -> TorpedoTargetingValidationResult:
	var result := TorpedoTargetingValidationResult.new()
	result.valid = true
	result.profile = attack_profile
	return result


static func rejected(reason: StringName) -> TorpedoTargetingValidationResult:
	var result := TorpedoTargetingValidationResult.new()
	result.failure_reason = reason
	return result
