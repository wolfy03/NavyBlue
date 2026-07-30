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

@export var maximum_dive_target_angle_degrees: float = 25.0
# Deprecated compatibility alias for older resources.
@export var dive_entry_distance_m: float = 900.0
@export var automatic_release_distance_m: float = 180.0


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
	if maximum_dive_target_angle_degrees <= 0.0 \
			or maximum_dive_target_angle_degrees > 90.0:
		errors.append("maximum target angle must be in (0, 90].")
	if dive_entry_distance_m <= 0.0:
		errors.append("dive_entry_distance_m must be positive.")
	if automatic_release_distance_m <= 0.0:
		errors.append("automatic_release_distance_m must be positive.")
	return errors
