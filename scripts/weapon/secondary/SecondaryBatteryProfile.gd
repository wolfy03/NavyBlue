extends Resource
class_name SecondaryBatteryProfile

enum IdleBehavior {
	HOLD_LAST_AIM,
	RETURN_TO_REST,
	FACE_OUTBOARD,
}

## How the battery's mounts time their shots relative to each other.
##   INDEPENDENT - every mount fires the moment it is individually ready.
##   SALVO       - mounts wait and fire together (reserved, not implemented).
##   RIPPLE      - mounts fire in a staggered sequence (reserved).
## Only INDEPENDENT is implemented; the others validate but fall back to it.
enum FireCoordinationMode {
	INDEPENDENT,
	SALVO,
	RIPPLE,
}

const SUPPORTED_FIRE_COORDINATION_MODES: Array[int] = [
	FireCoordinationMode.INDEPENDENT,
]

@export var enabled := true
@export var hold_fire := false
@export var fire_coordination_mode: FireCoordinationMode = \
	FireCoordinationMode.INDEPENDENT

@export_category("Evaluation Budget")
## Longest a ready gun may wait for its turn when budgeted evaluation is on.
## The budget is derived from this, so adding mounts raises the per-frame
## budget instead of delaying shots.
@export_range(0.016, 0.5, 0.001) var maximum_mount_evaluation_delay_sec := 0.1
@export_range(1, 64, 1) var minimum_mount_evaluation_budget := 4
@export_range(1, 256, 1) var maximum_mount_evaluation_budget := 64

@export_category("Line of Fire")
## A blocked/clear verdict is reused for this long unless the aim point moves
## past the recheck distance, so the ray query does not run per mount per frame.
@export_range(0.0, 1.0, 0.01) var line_of_fire_cache_interval_sec := 0.1
@export_range(0.0, 200.0, 1.0) var line_of_fire_recheck_distance_m := 10.0

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
	if not FireCoordinationMode.values().has(int(fire_coordination_mode)):
		errors.append("fire_coordination_mode must be a valid enum value.")
	return errors


## The mode actually used at runtime. Values that are valid enum entries but
## not implemented yet degrade to INDEPENDENT instead of disabling the battery.
func get_effective_fire_coordination_mode() -> FireCoordinationMode:
	if SUPPORTED_FIRE_COORDINATION_MODES.has(int(fire_coordination_mode)):
		return fire_coordination_mode
	return FireCoordinationMode.INDEPENDENT


func is_fire_coordination_mode_supported() -> bool:
	return SUPPORTED_FIRE_COORDINATION_MODES.has(int(fire_coordination_mode))


func _is_finite_positive(value: float) -> bool:
	return is_finite(value) and value > 0.0


func _is_finite_nonnegative(value: float) -> bool:
	return is_finite(value) and value >= 0.0


func is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)

