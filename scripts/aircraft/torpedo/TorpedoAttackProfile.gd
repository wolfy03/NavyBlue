extends Resource
class_name TorpedoAttackProfile

@export_category("Attack Run")
@export var minimum_attack_run_distance_m := 700.0
@export var approach_distance_m := 500.0
@export var escape_distance_m := 650.0
@export var minimum_direction_drag_m := 15.0
@export var multi_squadron_attack_spacing_m := 180.0
@export var release_grace_distance_m := 120.0

@export_category("Altitude")
@export var attack_entry_altitude_m := 45.0
@export var release_altitude_m := 25.0
@export var maximum_release_altitude_m := 40.0
@export var escape_altitude_m := 120.0

@export_category("Speed")
@export var attack_run_speed_mps := 65.0
@export var minimum_release_speed_mps := 45.0
@export var maximum_release_speed_mps := 90.0

@export_category("Alignment")
@export var alignment_tolerance_deg := 5.0
@export var release_point_tolerance_m := 20.0

@export_category("Presentation")
@export var preview_height_offset_m := 3.0
@export var targeting_refresh_interval_sec := 0.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if minimum_attack_run_distance_m <= 0.0:
		errors.append("minimum_attack_run_distance_m must be positive.")
	if approach_distance_m < 0.0 or escape_distance_m < 0.0:
		errors.append("approach and escape distances must not be negative.")
	if minimum_direction_drag_m < 0.0:
		errors.append("minimum_direction_drag_m must not be negative.")
	if multi_squadron_attack_spacing_m < 0.0:
		errors.append("multi_squadron_attack_spacing_m must not be negative.")
	if release_grace_distance_m < 0.0:
		errors.append("release_grace_distance_m must not be negative.")
	if attack_entry_altitude_m <= 0.0 or release_altitude_m <= 0.0:
		errors.append("attack and release altitudes must be positive.")
	if maximum_release_altitude_m < release_altitude_m:
		errors.append("maximum_release_altitude_m must cover release_altitude_m.")
	if escape_altitude_m < maximum_release_altitude_m:
		errors.append("escape_altitude_m must exceed the release envelope.")
	if attack_run_speed_mps <= 0.0:
		errors.append("attack_run_speed_mps must be positive.")
	if minimum_release_speed_mps <= 0.0 \
			or maximum_release_speed_mps < minimum_release_speed_mps:
		errors.append("release speed range is invalid.")
	if attack_run_speed_mps < minimum_release_speed_mps \
			or attack_run_speed_mps > maximum_release_speed_mps:
		errors.append(
			"attack_run_speed_mps must lie within the release speed range."
		)
	if alignment_tolerance_deg <= 0.0 \
			or alignment_tolerance_deg > 180.0:
		errors.append(
			"alignment_tolerance_deg must be within (0, 180]."
		)
	if release_point_tolerance_m <= 0.0:
		errors.append("release_point_tolerance_m must be positive.")
	if targeting_refresh_interval_sec < 0.0:
		errors.append("targeting_refresh_interval_sec must not be negative.")
	return errors
