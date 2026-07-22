extends Resource
class_name BattlefieldSettings

@export_category("World (meters)")
@export var map_size_m := Vector2(20000.0, 20000.0)
@export var sea_level_m := 0.0
@export var boundary_margin_m := 250.0

@export_category("Navigation")
@export var waypoint_reach_radius_m := 100.0
@export var destination_reach_radius_m := 140.0
@export var path_deviation_threshold_m := 320.0
@export var path_recalculation_interval_sec := 1.0
@export var distant_path_recalculation_interval_sec := 2.5
@export var minimum_path_segment_m := 35.0
@export var path_collinear_tolerance_deg := 4.0
@export var local_avoidance_radius_m := 500.0
@export var local_avoidance_prediction_sec := 15.0
@export var local_avoidance_update_interval_sec := 0.35
@export var local_avoidance_hold_sec := 2.0

@export_category("Camera")
@export var camera_min_height_m := 80.0
@export var camera_max_height_m := 7000.0
@export var camera_default_height_m := 1200.0
@export var camera_boundary_padding_m := 300.0
@export var camera_min_move_speed_mps := 450.0
@export var camera_max_move_speed_mps := 1200.0

@export_category("Debug")
@export var debug_draw_enabled := false
@export var debug_grid_spacing_m := 1000.0

func get_half_extents_m() -> Vector2:
	return map_size_m * 0.5
