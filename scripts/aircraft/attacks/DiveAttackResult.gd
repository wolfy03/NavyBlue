extends RefCounted
class_name DiveAttackResult

var successful := false
var release_started := false
var release_failed := false
var requested_count := 0
var released_count := 0
var failed_count := 0
var skipped_count := 0
var cancelled := false
var remaining_ammunition := 0
var final_state: String


func to_dictionary() -> Dictionary:
	return {
		"successful": successful,
		"release_started": release_started,
		"release_failed": release_failed,
		"requested_count": requested_count,
		"released_count": released_count,
		"failed_count": failed_count,
		"skipped_count": skipped_count,
		"cancelled": cancelled,
		"remaining_ammunition": remaining_ammunition,
		"final_state": final_state,
	}
