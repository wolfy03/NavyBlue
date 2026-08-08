extends RefCounted
class_name DiveBombAircraftAttackState

enum State {
	WAITING,
	APPROACHING,
	ALIGNING,
	DIVING,
	RELEASED,
	PULLING_OUT,
	REGROUPING,
	FAILED,
	DESTROYED,
}

var aircraft_ref: WeakRef
var aircraft_instance_id := 0
var aircraft_combat_id := 0
var aircraft_slot_id := 0

var solution: DiveBombAttackSolution
var state := State.WAITING

var locked_attack_direction := Vector3.FORWARD
var locked_dive_direction := Vector3.ZERO

var dive_elapsed_sec := 0.0
var alignment_elapsed_sec := 0.0
var alignment_timeout_sec := 0.0
var pull_out_elapsed_sec := 0.0

## Live ALIGNING telemetry. These describe the real velocity track and the
## lightweight target heading, not a visual transform.
var current_heading := Vector3.FORWARD
var desired_heading := Vector3.FORWARD
var current_heading_error_degrees := 0.0
var applied_turn_step_degrees := 0.0
var current_turn_rate_degrees_sec := 0.0
var final_solution_ready := false
var final_solution_revision := 0

var release_block_reason := DiveBombReleaseBlockReason.Type.NONE

var release_attempted := false
var released := false
var ammunition_consumed := false
var degraded_release_used := false
## Transient release refusals retried so far, and the cooldown until the
## next attempt. Retries are fully per-aircraft.
var release_retry_count := 0
var release_retry_cooldown_sec := 0.0
var last_release_altitude_m := 0.0
var last_release_remaining_m := 0.0
var last_predicted_forward_error_m := 0.0
var last_predicted_lateral_error_m := 0.0


func get_aircraft() -> AircraftUnit:
	var value: Variant = aircraft_ref.get_ref() \
		if aircraft_ref != null else null
	if value == null or not is_instance_valid(value):
		return null
	return value as AircraftUnit


func is_attack_resolved() -> bool:
	return state in [
		State.RELEASED,
		State.PULLING_OUT,
		State.REGROUPING,
		State.FAILED,
		State.DESTROYED,
	]


func is_terminal() -> bool:
	return state in [State.REGROUPING, State.FAILED, State.DESTROYED]
