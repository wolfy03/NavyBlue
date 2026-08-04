extends RefCounted
class_name DiveBombAttackSolution
## One dive-bombing attack geometry, solved backwards from where the bomb must
## land.
##
## The three positions are deliberately distinct and must never be collapsed
## into a single "target position":
##   predicted_impact_position - where the bomb should land
##   release_position          - where the aircraft must let the bomb go
##   dive_entry_position       - where the aircraft must start its dive
##
## Holds values only: no aircraft or target Object references.

var valid := false
var failure_reason: StringName = &""

var target_position_at_solve := Vector3.ZERO
var target_velocity := Vector3.ZERO

var predicted_impact_position := Vector3.ZERO
var release_position := Vector3.ZERO
var dive_entry_position := Vector3.ZERO
var approach_position := Vector3.ZERO

var attack_direction := Vector3.FORWARD

var approach_time_sec := 0.0
var dive_time_to_release_sec := 0.0
var bomb_fall_time_sec := 0.0
var release_delay_sec := 0.0
var total_time_to_impact_sec := 0.0

var release_altitude_m := 0.0
var dive_entry_altitude_m := 0.0

var horizontal_dive_distance_m := 0.0
var bomb_horizontal_travel_m := 0.0

var predicted_bomb_velocity := Vector3.ZERO
var solution_iteration_count := 0

var revision := 0
var solved_at_mission_time_sec := 0.0


static func failed(reason: StringName) -> DiveBombAttackSolution:
	var solution := DiveBombAttackSolution.new()
	solution.failure_reason = reason
	return solution


func duplicate_solution() -> DiveBombAttackSolution:
	var copy := DiveBombAttackSolution.new()
	copy.valid = valid
	copy.failure_reason = failure_reason
	copy.target_position_at_solve = target_position_at_solve
	copy.target_velocity = target_velocity
	copy.predicted_impact_position = predicted_impact_position
	copy.release_position = release_position
	copy.dive_entry_position = dive_entry_position
	copy.approach_position = approach_position
	copy.attack_direction = attack_direction
	copy.approach_time_sec = approach_time_sec
	copy.dive_time_to_release_sec = dive_time_to_release_sec
	copy.bomb_fall_time_sec = bomb_fall_time_sec
	copy.release_delay_sec = release_delay_sec
	copy.total_time_to_impact_sec = total_time_to_impact_sec
	copy.release_altitude_m = release_altitude_m
	copy.dive_entry_altitude_m = dive_entry_altitude_m
	copy.horizontal_dive_distance_m = horizontal_dive_distance_m
	copy.bomb_horizontal_travel_m = bomb_horizontal_travel_m
	copy.predicted_bomb_velocity = predicted_bomb_velocity
	copy.solution_iteration_count = solution_iteration_count
	copy.revision = revision
	copy.solved_at_mission_time_sec = solved_at_mission_time_sec
	return copy


func to_debug_dictionary() -> Dictionary:
	return {
		"solution_valid": valid,
		"solution_failure_reason": failure_reason,
		"predicted_impact_position": predicted_impact_position,
		"planned_release_position": release_position,
		"planned_dive_entry_position": dive_entry_position,
		"planned_approach_position": approach_position,
		"attack_direction": attack_direction,
		"approach_time_sec": approach_time_sec,
		"dive_time_to_release_sec": dive_time_to_release_sec,
		"bomb_fall_time_sec": bomb_fall_time_sec,
		"total_time_to_impact_sec": total_time_to_impact_sec,
		"horizontal_dive_distance_m": horizontal_dive_distance_m,
		"bomb_horizontal_travel_m": bomb_horizontal_travel_m,
		"solution_revision": revision,
		"solution_iteration_count": solution_iteration_count,
	}
