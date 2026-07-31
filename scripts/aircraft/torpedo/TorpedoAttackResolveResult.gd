extends RefCounted
class_name TorpedoAttackResolveResult

var success := false
var command: TorpedoAttackCommand
var failure_reason: StringName


static func completed(
		resolved_command: TorpedoAttackCommand
) -> TorpedoAttackResolveResult:
	var result := TorpedoAttackResolveResult.new()
	result.success = resolved_command != null
	result.command = resolved_command
	return result


static func failed(reason: StringName) -> TorpedoAttackResolveResult:
	var result := TorpedoAttackResolveResult.new()
	result.failure_reason = reason
	return result
