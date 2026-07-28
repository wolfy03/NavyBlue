extends Resource
class_name FighterCombatData

@export_category("Pilot")
@export_range(0.0, 1.0, 0.01) var pilot_skill: float = 0.5
@export_range(0.0, 1.0, 0.01) var tracking_skill: float = 0.5
@export_range(0.0, 1.0, 0.01) var evasion_skill: float = 0.5

@export_category("Detection")
@export var detection_range_m: float = 2500.0
@export var disengage_range_m: float = 2200.0

@export_category("Engagement")
@export var preferred_engagement_range_m: float = 320.0
@export var firing_cone_degrees: float = 60.0
@export var lock_time_sec: float = 0.6
@export var separation_distance_m: float = 650.0
@export_range(1, 20, 1) var maximum_attack_passes: int = 6

@export_category("Accuracy")
@export_range(0.0, 1.0, 0.01) var base_accuracy: float = 0.35
@export_range(0.0, 1.0, 0.01) var minimum_accuracy: float = 0.03
@export_range(0.0, 1.0, 0.01) var maximum_accuracy: float = 0.85
@export var optimal_range_m: float = 300.0
@export var angular_accuracy_weight: float = 1.0
@export var relative_speed_penalty: float = 0.25
@export var target_evasion_weight: float = 0.35

@export_category("Targeting")
@export var bomber_priority_bonus: float = 35.0
@export var torpedo_bomber_priority_bonus: float = 45.0
@export var fighter_priority_bonus: float = 10.0
@export var distance_weight: float = 1.0
@export var duplicate_target_penalty: float = 20.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if firing_cone_degrees <= 0.0 or firing_cone_degrees > 180.0:
		errors.append("firing_cone_degrees must be in (0, 180].")
	if detection_range_m <= 0.0:
		errors.append("detection_range_m must be positive.")
	if preferred_engagement_range_m <= 0.0:
		errors.append("preferred_engagement_range_m must be positive.")
	if disengage_range_m < preferred_engagement_range_m:
		errors.append(
			"disengage_range_m must not be less than preferred range."
		)
	if minimum_accuracy > maximum_accuracy:
		errors.append("minimum_accuracy must not exceed maximum_accuracy.")
	if optimal_range_m <= 0.0:
		errors.append("optimal_range_m must be positive.")
	if lock_time_sec < 0.0:
		errors.append("lock_time_sec cannot be negative.")
	if maximum_attack_passes <= 0:
		errors.append("maximum_attack_passes must be positive.")
	return errors
