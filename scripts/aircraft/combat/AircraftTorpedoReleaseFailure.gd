extends RefCounted
class_name AircraftTorpedoReleaseFailure

var aircraft_id := 0
var reason: StringName = &""
var retryable := false
var attempt_count := 0


static func create(
		id: int,
		failure_reason: StringName,
		can_retry: bool,
		attempts: int = 0
) -> AircraftTorpedoReleaseFailure:
	var failure := AircraftTorpedoReleaseFailure.new()
	failure.aircraft_id = id
	failure.reason = failure_reason
	failure.retryable = can_retry
	failure.attempt_count = attempts
	return failure
