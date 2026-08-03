extends RefCounted
class_name GunneryDebugSnapshot
## Development-only view of one weapon group's current fire-control solution.
## Built on demand; never rendered unless a debug consumer asks for it.

var shooter_instance_id := 0
var target_instance_id := 0
var aim_source := 0
var weapon_group_id: StringName = &""

var target_actual_position := Vector3.ZERO
var target_observed_position := Vector3.ZERO

var target_actual_velocity := Vector3.ZERO
var target_observed_velocity := Vector3.ZERO

var ideal_aim_point := Vector3.ZERO
var actual_aim_point := Vector3.ZERO

var projectile_flight_time_sec := 0.0

var range_error_m := 0.0
var lateral_error_m := 0.0
var shell_dispersion_sigma_m := 0.0

var confidence := 0.0
var correction_level := 0.0
var salvo_index := 0
var fire_command_id := 0
var salvo_started_time_sec := 0.0
var salvo_grouping_window_sec := 0.0
var shells_resolved_in_salvo := 0
var turrets_expected_in_salvo := 0
var tracking_target_instance_id := 0
var tracking_state_reset_count := 0
var last_tracking_reset_reason: StringName = &""
var failure_reason: StringName = &""
