extends RefCounted
class_name SecondaryBatteryDebugSnapshot

var enabled := false
var hold_fire := false
var current_target_instance_id := 0
var current_target_score := 0.0
var candidate_count := 0
var total_mount_count := 0
var valid_mount_count := 0
var engaging_mount_count := 0
var firing_mount_count := 0
var maximum_range_m := 0.0
var scan_elapsed_sec := 0.0
var target_switch_elapsed_sec := 0.0
var predicted_impact_position := Vector3.ZERO
var actual_aim_position := Vector3.ZERO
var last_target_change_reason: StringName = &""
var last_fire_control_failure: StringName = &""

