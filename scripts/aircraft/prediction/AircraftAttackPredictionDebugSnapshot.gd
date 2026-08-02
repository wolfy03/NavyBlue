extends RefCounted
class_name AircraftAttackPredictionDebugSnapshot

# Read-only view of an AI attack's current predictive solution, for a debug
# overlay or logging. Built on demand (never printed automatically) so it costs
# nothing during normal play. Fields left at defaults are simply not populated
# by the caller that produced the snapshot.

var target_instance_id := 0
var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO

var predicted_target_center := Vector3.ZERO
var predicted_collision_point := Vector3.ZERO
var release_point := Vector3.ZERO
var entry_point := Vector3.ZERO

var arming_distance_m := 0.0
var collision_margin_m := 0.0
var prediction_error_margin_m := 0.0
var safe_run_distance_m := 0.0

var aircraft_approach_time_sec := 0.0
var water_entry_time_sec := 0.0
var torpedo_run_time_sec := 0.0
var total_impact_time_sec := 0.0

var solution_revision := 0
var solution_locked := false
var replan_count := 0

var attack_state: StringName = &""
var last_repath_reason: StringName = &""
var prediction_failure_reason: StringName = &""
