extends Resource
class_name DiveBomberCombatData

@export var dive_entry_altitude_m: float = 350.0
@export var dive_angle_degrees: float = 55.0
@export var dive_speed_mps: float = 210.0
@export var approach_distance_m: float = 900.0
@export var dive_entry_horizontal_distance_m: float = 250.0

@export var minimum_dive_time_before_release_sec: float = 0.5
@export var minimum_release_altitude_m: float = 70.0
@export var maximum_release_altitude_m: float = 160.0

@export_category("Automatic Release")
@export var automatic_release_altitude_m: float = 90.0
@export var release_altitude_tolerance_m: float = 8.0

@export var automatic_pull_out_altitude_m: float = 45.0
@export_range(0.1, 1.0, 0.05)
var pull_out_aircraft_ratio: float = 0.5
@export var pull_out_distance_m: float = 500.0
@export var pull_out_climb_angle_degrees: float = 25.0

@export_category("Individual Attack")
@export var individual_dive_split_distance_m := 700.0
@export var quick_dive_alignment_time_sec := 0.5
@export var quick_dive_max_heading_error_degrees := 25.0
@export var minimum_dive_lane_spacing_m := 0.0

@export_category("Regroup")
@export var regroup_after_attack := true
@export var regroup_distance_m := 500.0
@export var regroup_timeout_sec := 8.0
@export_range(0.0, 1.0, 0.05) var regroup_completion_ratio := 0.7

@export_category("Target Pass")
@export var target_pass_margin_m: float = 75.0
@export var target_pass_check_max_altitude_m: float = 160.0
@export var require_release_attempt_before_pass_abort := true

@export var maximum_dive_target_angle_degrees: float = 25.0

@export_category("Release Window")
## Horizontal distance from one aircraft to its planned release point.
@export var release_position_tolerance_m := 60.0
## Maximum horizontal error between the impact predicted from one aircraft's
## current state and the planned impact point.
@export var maximum_predicted_impact_error_m := 90.0
## Maximum angle between one aircraft's actual horizontal track and its locked
## attack direction.
@export var maximum_release_heading_error_degrees := 12.0
## The squadron drops when the live-predicted impact has swept to within this
## forward distance of the intended point. Small values release closer to the
## exact crossing; too small can miss the crossing between physics frames.
@export var release_impact_trigger_margin_m := 12.0

@export_category("Bombing Skill")
## The single runtime source of dive-bombing accuracy.
@export var accuracy_profile: DiveBombAccuracyProfile
var _fallback_accuracy_profile: DiveBombAccuracyProfile

@export_category("Target Acquisition")
## When a dive-bomb order designates a world position, hostile ships within
## this radius of the designation are automatically acquired as the actual
## attack target. Shared by AI and player orders.
@export var auto_acquire_ship_near_designation := true
@export_range(0.0, 2000.0, 10.0)
var target_acquisition_radius_m := 250.0

func get_accuracy_profile() -> DiveBombAccuracyProfile:
	if accuracy_profile != null:
		return accuracy_profile
	if _fallback_accuracy_profile == null:
		_fallback_accuracy_profile = DiveBombAccuracyProfile.new()
	return _fallback_accuracy_profile


func get_target_acquisition_radius_m() -> float:
	return maxf(target_acquisition_radius_m, 0.0) \
		if auto_acquire_ship_near_designation else 0.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if dive_entry_altitude_m <= 0.0:
		errors.append("dive_entry_altitude_m must be positive.")
	if dive_angle_degrees <= 0.0 or dive_angle_degrees >= 90.0:
		errors.append("dive_angle_degrees must be in (0, 90).")
	if dive_speed_mps <= 0.0:
		errors.append("dive_speed_mps must be positive.")
	if approach_distance_m <= 0.0:
		errors.append("approach_distance_m must be positive.")
	if dive_entry_horizontal_distance_m < 0.0:
		errors.append(
			"dive_entry_horizontal_distance_m cannot be negative."
		)
	if minimum_dive_time_before_release_sec < 0.0:
		errors.append("minimum dive time cannot be negative.")
	if minimum_release_altitude_m < 0.0 \
			or maximum_release_altitude_m < minimum_release_altitude_m:
		errors.append("release altitude range is invalid.")
	if maximum_release_altitude_m < automatic_release_altitude_m:
		errors.append(
			"maximum_release_altitude_m must be greater than or equal "
			+ "to automatic_release_altitude_m."
		)
	if automatic_release_altitude_m < minimum_release_altitude_m:
		errors.append(
			"automatic_release_altitude_m must be greater than or equal "
			+ "to minimum_release_altitude_m."
		)
	if minimum_release_altitude_m <= automatic_pull_out_altitude_m:
		errors.append(
			"minimum_release_altitude_m must be greater than "
			+ "automatic_pull_out_altitude_m."
		)
	if release_altitude_tolerance_m < 0.0:
		errors.append(
			"release_altitude_tolerance_m must not be negative."
		)
	if automatic_pull_out_altitude_m < 0.0:
		errors.append("automatic pull-out altitude cannot be negative.")
	if pull_out_aircraft_ratio < 0.1 \
			or pull_out_aircraft_ratio > 1.0:
		errors.append("pull_out_aircraft_ratio must be in [0.1, 1.0].")
	if pull_out_distance_m <= 0.0:
		errors.append("pull_out_distance_m must be positive.")
	if pull_out_climb_angle_degrees <= 0.0 \
			or pull_out_climb_angle_degrees >= 90.0:
		errors.append("pull-out climb angle must be in (0, 90).")
	if individual_dive_split_distance_m < 0.0:
		errors.append("individual_dive_split_distance_m cannot be negative.")
	if quick_dive_alignment_time_sec < 0.0:
		errors.append("quick_dive_alignment_time_sec cannot be negative.")
	if quick_dive_max_heading_error_degrees < 0.0 \
			or quick_dive_max_heading_error_degrees > 180.0:
		errors.append(
			"quick_dive_max_heading_error_degrees must be in [0, 180]."
		)
	if minimum_dive_lane_spacing_m < 0.0:
		errors.append("minimum_dive_lane_spacing_m cannot be negative.")
	if regroup_distance_m < 0.0:
		errors.append("regroup_distance_m cannot be negative.")
	if regroup_timeout_sec < 0.0:
		errors.append("regroup_timeout_sec cannot be negative.")
	if regroup_completion_ratio < 0.0 or regroup_completion_ratio > 1.0:
		errors.append("regroup_completion_ratio must be in [0, 1].")
	if target_pass_margin_m < 0.0:
		errors.append("target_pass_margin_m must not be negative.")
	if target_pass_check_max_altitude_m <= 0.0:
		errors.append(
			"target_pass_check_max_altitude_m must be greater than zero."
		)
	if maximum_dive_target_angle_degrees <= 0.0 \
			or maximum_dive_target_angle_degrees > 90.0:
		errors.append("maximum target angle must be in (0, 90].")
	if accuracy_profile != null:
		for profile_error in accuracy_profile.validate():
			errors.append("accuracy_profile: %s" % profile_error)
	if target_acquisition_radius_m < 0.0:
		errors.append("target_acquisition_radius_m must not be negative.")
	return errors
