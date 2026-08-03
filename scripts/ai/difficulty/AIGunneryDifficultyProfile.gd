extends Resource
class_name AIGunneryDifficultyProfile
## AI-side gunnery difficulty tuning. Multiplies the weapon-owned mechanical
## accuracy (GunneryWeaponAccuracyProfile) and the crew-derived observation
## quality. Player manual aim never consults this resource.

@export var difficulty_id: StringName = &"normal"

@export_category("Observation")
@export var position_observation_error_multiplier := 1.0
@export var velocity_observation_error_multiplier := 1.0
@export var observation_delay_multiplier := 1.0
@export var base_position_observation_error_m := 25.0
@export var base_velocity_observation_error_mps := 1.5
@export var minimum_observation_delay_sec := 0.15
@export var maximum_observation_delay_sec := 1.0

@export_category("Fire Control Error")
@export var range_error_multiplier := 1.0
@export var lateral_error_multiplier := 1.0
@export var shell_dispersion_multiplier := 1.0
@export var salvo_correction_multiplier := 1.0
## Scales the weapon profile's minimum error floors so even Hard AI with an
## elite crew never reaches zero error.
@export var minimum_error_multiplier := 1.0

@export_category("Solution Cadence")
@export var aim_solution_refresh_interval_sec := 0.2
@export var aim_solution_repath_threshold_m := 10.0
@export var base_salvo_correction_strength := 0.25
@export var minimum_corrected_bias_ratio := 0.4
## Observed velocity change (m/s between observations) treated as a sharp
## maneuver: confidence drops and accumulated salvo correction partially
## resets.
@export var velocity_change_alert_mps := 3.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if minimum_observation_delay_sec < 0.0:
		errors.append("minimum_observation_delay_sec must not be negative.")
	if maximum_observation_delay_sec < minimum_observation_delay_sec:
		errors.append(
			"maximum_observation_delay_sec must be >= minimum_observation_delay_sec."
		)
	if aim_solution_refresh_interval_sec <= 0.0:
		errors.append("aim_solution_refresh_interval_sec must be positive.")
	if minimum_error_multiplier <= 0.0:
		errors.append("minimum_error_multiplier must be positive.")
	if minimum_corrected_bias_ratio < 0.0 \
			or minimum_corrected_bias_ratio > 1.0:
		errors.append("minimum_corrected_bias_ratio must be within 0..1.")
	return errors
