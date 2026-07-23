extends Resource
class_name ShipAIRoleProfile

@export var role_id: StringName = &"default"
@export_range(0.1, 1.0, 0.01) var preferred_range_ratio := 0.75
@export var tactical_clearance_m := 300.0

@export_category("Target Weights")
@export var distance_weight := 25.0
@export var recent_damage_to_self_weight := 0.8
@export var recent_damage_to_allies_weight := 0.25
@export var combat_power_weight := 15.0
@export var strategic_value_weight := 10.0
@export var current_target_bonus := 15.0
@export var aiming_at_self_bonus := 12.0
@export var low_health_finish_bonus := 8.0
@export var focus_fire_penalty_weight := 10.0

@export_category("Target Switching")
@export var minimum_target_lock_sec := 8.0
@export var target_switch_ratio := 1.25
@export var emergency_threat_threshold := 40.0

@export_category("Class Preferences")
@export var target_class_weights: Dictionary = {}
