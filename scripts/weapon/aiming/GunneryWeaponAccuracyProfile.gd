extends Resource
class_name GunneryWeaponAccuracyProfile
## Mechanical accuracy owned by the weapon itself: base fire-control error and
## per-shell dispersion at a reference range, plus how each grows with range.
## Difficulty and crew multipliers are applied on top by
## GunneryAccuracyResolver.

@export var reference_range_m := 5000.0

@export_category("Base Error (1 sigma at reference range)")
@export var base_range_error_m := 40.0
@export var base_lateral_error_m := 25.0
@export var base_shell_dispersion_m := 15.0

@export_category("Range Growth")
@export var range_error_growth_exponent := 1.0
@export var lateral_error_growth_exponent := 1.0
@export var dispersion_growth_exponent := 1.0
@export var minimum_range_factor := 0.25
@export var maximum_range_factor := 3.0

@export_category("Error Floors")
## Absolute floors so no difficulty or crew combination reaches zero error.
@export var minimum_range_error_m := 2.0
@export var minimum_lateral_error_m := 2.0
@export var minimum_shell_dispersion_m := 1.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if reference_range_m <= 0.0:
		errors.append("reference_range_m must be positive.")
	if minimum_range_factor <= 0.0:
		errors.append("minimum_range_factor must be positive.")
	if maximum_range_factor < minimum_range_factor:
		errors.append(
			"maximum_range_factor must be >= minimum_range_factor."
		)
	if minimum_range_error_m < 0.0 \
			or minimum_lateral_error_m < 0.0 \
			or minimum_shell_dispersion_m < 0.0:
		errors.append("Minimum error floors must not be negative.")
	return errors
