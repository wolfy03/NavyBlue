extends Resource
class_name AIDifficultyProfile

@export var difficulty_id: StringName = &"normal"
@export var fleet_update_interval_sec := 1.5
@export var role_update_interval_sec := 4.0
@export var tactical_position_update_interval_sec := 3.0
@export var tracker_cleanup_interval_sec := 1.5
@export var reaction_delay_sec := 0.4
@export var fleet_recommendation_multiplier := 1.0
@export var emergency_response_multiplier := 1.0
@export var focus_fire_efficiency := 1.0
@export var tactical_position_error_m := 150.0
@export var tactical_error_hold_sec := 14.0
