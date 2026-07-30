extends Resource
class_name AIDifficultyProfile

@export var difficulty_id: StringName = &"normal"
@export var reaction_delay_sec := 0.4
@export_category("Scheduling Multipliers")
@export var fleet_update_interval_multiplier := 1.0
@export var role_update_interval_multiplier := 1.0
@export var tactical_update_interval_multiplier := 1.0
@export var cleanup_interval_multiplier := 1.0
@export_category("Decision Quality")
@export var fleet_recommendation_multiplier := 1.0
@export var emergency_response_multiplier := 1.0
@export var focus_fire_efficiency := 1.0
@export var tactical_position_error_m := 150.0
@export var tactical_error_hold_sec := 14.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if reaction_delay_sec < 0.0:
		errors.append("reaction_delay_sec must not be negative.")
	if fleet_update_interval_multiplier <= 0.0:
		errors.append("fleet_update_interval_multiplier must be greater than zero.")
	if role_update_interval_multiplier <= 0.0:
		errors.append("role_update_interval_multiplier must be greater than zero.")
	if tactical_update_interval_multiplier <= 0.0:
		errors.append("tactical_update_interval_multiplier must be greater than zero.")
	if cleanup_interval_multiplier <= 0.0:
		errors.append("cleanup_interval_multiplier must be greater than zero.")
	return errors
