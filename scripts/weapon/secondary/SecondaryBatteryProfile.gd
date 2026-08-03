extends Resource
class_name SecondaryBatteryProfile

enum IdleBehavior {
	HOLD_LAST_AIM,
	RETURN_TO_REST,
	FACE_OUTBOARD,
}

@export var enabled := true
@export var hold_fire := false

@export_category("Targeting")
@export var scan_interval_sec := 0.3
@export var target_switch_cooldown_sec := 2.0
@export var target_switch_score_ratio := 1.25
@export var minimum_engaging_mount_count := 1
@export var maximum_candidates_per_scan := 32
@export var idle_behavior: IdleBehavior = IdleBehavior.RETURN_TO_REST

@export_category("Priority")
@export var prefer_main_target := true
@export var main_target_score_bonus := 0.15
@export var distance_score_weight := 1.0
@export var available_mount_score_weight := 0.35
@export var threat_score_weight := 0.25
@export var target_size_score_weight := 0.1


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not _is_finite_positive(scan_interval_sec):
		errors.append("scan_interval_sec must be positive.")
	if not _is_finite_nonnegative(target_switch_cooldown_sec):
		errors.append("target_switch_cooldown_sec must not be negative.")
	if not is_finite(target_switch_score_ratio) \
			or target_switch_score_ratio < 1.0:
		errors.append("target_switch_score_ratio must be at least 1.")
	if minimum_engaging_mount_count < 1:
		errors.append("minimum_engaging_mount_count must be at least 1.")
	if maximum_candidates_per_scan < 1:
		errors.append("maximum_candidates_per_scan must be at least 1.")
	var weights := {
		"main_target_score_bonus": main_target_score_bonus,
		"distance_score_weight": distance_score_weight,
		"available_mount_score_weight": available_mount_score_weight,
		"threat_score_weight": threat_score_weight,
		"target_size_score_weight": target_size_score_weight,
	}
	for property_name: String in weights:
		if not _is_finite_nonnegative(float(weights[property_name])):
			errors.append("%s must not be negative." % property_name)
	return errors


func _is_finite_positive(value: float) -> bool:
	return is_finite(value) and value > 0.0


func _is_finite_nonnegative(value: float) -> bool:
	return is_finite(value) and value >= 0.0


func is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

