extends RefCounted
class_name AircraftPayloadReleasePassResult

var requested_count := 0
var released_count := 0
var failed_count := 0
var skipped_count := 0
var cancelled_count := 0
var cancelled := false


func is_successful() -> bool:
	return released_count > 0


func to_dictionary() -> Dictionary:
	return {
		"requested_count": requested_count,
		"released_count": released_count,
		"failed_count": failed_count,
		"skipped_count": skipped_count,
		"cancelled_count": cancelled_count,
		"cancelled": cancelled,
	}
