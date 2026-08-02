extends RefCounted
class_name TorpedoAttackResolveResult

enum FailureDisposition {
	RETRYABLE,
	FATAL,
}

var success := false
var command: TorpedoAttackCommand
var failure_reason: StringName
var failure_disposition: FailureDisposition = FailureDisposition.FATAL


static func completed(
		resolved_command: TorpedoAttackCommand
) -> TorpedoAttackResolveResult:
	var result := TorpedoAttackResolveResult.new()
	result.success = resolved_command != null
	result.command = resolved_command
	return result


static func failed(
		reason: StringName,
		disposition: FailureDisposition = FailureDisposition.FATAL
) -> TorpedoAttackResolveResult:
	var result := TorpedoAttackResolveResult.new()
	result.failure_reason = reason
	result.failure_disposition = disposition
	return result
