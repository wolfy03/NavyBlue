extends RefCounted
class_name BattlePerformanceSnapshot
## Immutable view of one sampling window. Built only when a display or a
## benchmark asks for it, never every frame.

var fps := 0
var average_fps := 0.0
var one_percent_low_fps := 0.0
var minimum_fps := 0.0
var maximum_frame_time_ms := 0.0

var process_time_ms := 0.0
var physics_time_ms := 0.0

var draw_calls := 0
var rendered_objects := 0
var node_count := 0
var object_count := 0

var active_projectiles := 0
var active_secondary_projectiles := 0
var active_trails := 0
var peak_active_projectiles := 0
var peak_active_trails := 0

var secondary_ships := 0
var secondary_mounts_total := 0
var secondary_mounts_evaluated := 0
var secondary_mounts_ready := 0
var secondary_mounts_fired := 0

var group_rebuilds_requested := 0
var group_rebuilds_changed := 0
var lead_solves := 0
var accuracy_solves := 0
var line_of_fire_checks := 0
var candidate_mount_evaluations := 0


func to_dictionary() -> Dictionary:
	return {
		"fps": fps,
		"average_fps": average_fps,
		"one_percent_low_fps": one_percent_low_fps,
		"minimum_fps": minimum_fps,
		"maximum_frame_time_ms": maximum_frame_time_ms,
		"process_time_ms": process_time_ms,
		"physics_time_ms": physics_time_ms,
		"draw_calls": draw_calls,
		"rendered_objects": rendered_objects,
		"node_count": node_count,
		"object_count": object_count,
		"active_projectiles": active_projectiles,
		"active_secondary_projectiles": active_secondary_projectiles,
		"active_trails": active_trails,
		"peak_active_projectiles": peak_active_projectiles,
		"peak_active_trails": peak_active_trails,
		"secondary_ships": secondary_ships,
		"secondary_mounts_total": secondary_mounts_total,
		"secondary_mounts_evaluated": secondary_mounts_evaluated,
		"secondary_mounts_ready": secondary_mounts_ready,
		"secondary_mounts_fired": secondary_mounts_fired,
		"group_rebuilds_requested": group_rebuilds_requested,
		"group_rebuilds_changed": group_rebuilds_changed,
		"lead_solves": lead_solves,
		"accuracy_solves": accuracy_solves,
		"line_of_fire_checks": line_of_fire_checks,
		"candidate_mount_evaluations": candidate_mount_evaluations,
	}
