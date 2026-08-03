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

@export_category("Salvo Lifecycle")
@export var salvo_grouping_window_sec := 0.35


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not _is_finite(reference_range_m) or reference_range_m <= 0.0:
		errors.append("reference_range_m must be positive.")
	if not _is_finite(base_range_error_m) \
			or not _is_finite(base_lateral_error_m) \
			or not _is_finite(base_shell_dispersion_m) \
			or base_range_error_m < 0.0 \
			or base_lateral_error_m < 0.0 \
			or base_shell_dispersion_m < 0.0:
		errors.append("Base error values must not be negative.")
	if not _is_finite(range_error_growth_exponent) \
			or not _is_finite(lateral_error_growth_exponent) \
			or not _is_finite(dispersion_growth_exponent) \
			or range_error_growth_exponent < 0.0 \
			or lateral_error_growth_exponent < 0.0 \
			or dispersion_growth_exponent < 0.0:
		errors.append("Range growth exponents must not be negative.")
	if not _is_finite(minimum_range_factor) \
			or minimum_range_factor <= 0.0:
		errors.append("minimum_range_factor must be positive.")
	if not _is_finite(maximum_range_factor) \
			or maximum_range_factor < minimum_range_factor:
		errors.append(
			"maximum_range_factor must be >= minimum_range_factor."
		)
	if not _is_finite(minimum_range_error_m) \
			or not _is_finite(minimum_lateral_error_m) \
			or not _is_finite(minimum_shell_dispersion_m) \
			or minimum_range_error_m <= 0.0 \
			or minimum_lateral_error_m <= 0.0 \
			or minimum_shell_dispersion_m <= 0.0:
		errors.append("Minimum error floors must be positive.")
	if not _is_finite(salvo_grouping_window_sec) \
			or salvo_grouping_window_sec < 0.0:
		errors.append("salvo_grouping_window_sec must not be negative.")
	return errors


func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
