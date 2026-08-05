extends Resource
class_name DiveBombAccuracyProfile
## The single source of truth for dive-bombing accuracy.
##
## Runtime accuracy is resolved through this profile only: one deterministic
## aim offset per attack pass, rolled by DiveBombAttackPlanner after the
## target has been resolved. The ballistic solution itself is never degraded;
## the offset moves only the aim point.

## 1.0 aims exactly at the solved impact point; lower values scatter the aim
## inside a disc that widens toward minimum_accuracy_dispersion_m.
@export_range(0.0, 1.0, 0.01)
var base_accuracy := 1.0

## Dispersion radius (m) at accuracy 1.0. Zero means a perfect crew aims at
## the exact solved point.
@export var perfect_accuracy_dispersion_m := 0.0

## Dispersion radius (m) at accuracy 0.0.
@export var minimum_accuracy_dispersion_m := 150.0

## Future accuracy modifiers. Kept at zero (inactive) until the systems that
## feed them exist; they are exported now so profiles can be authored ahead.
@export var formation_size_multiplier := 0.0
@export var damage_state_multiplier := 0.0
@export var target_evasion_multiplier := 0.0


## Radius of the aim-dispersion disc for the given accuracy (defaults to the
## profile's own base accuracy). Linear: maximum at 0.0, perfect at 1.0.
func resolve_dispersion_radius_m(accuracy_override: float = -1.0) -> float:
	var accuracy := clampf(
		base_accuracy if accuracy_override < 0.0 else accuracy_override,
		0.0,
		1.0
	)
	return lerpf(
		maxf(minimum_accuracy_dispersion_m, 0.0),
		maxf(perfect_accuracy_dispersion_m, 0.0),
		accuracy
	)


## Deterministic aim offset for one attack pass. Pure function of the seed:
## the same squadron/target/pass always reproduces the same offset.
func resolve_dispersion_offset(deterministic_seed: int) -> Vector3:
	return DiveBombAccuracyMath.resolve_offset(
		base_accuracy,
		perfect_accuracy_dispersion_m,
		minimum_accuracy_dispersion_m,
		deterministic_seed
	)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if base_accuracy < 0.0 or base_accuracy > 1.0:
		errors.append("base_accuracy must be in [0, 1].")
	if perfect_accuracy_dispersion_m < 0.0:
		errors.append("perfect_accuracy_dispersion_m must not be negative.")
	if minimum_accuracy_dispersion_m < perfect_accuracy_dispersion_m:
		errors.append(
			"minimum_accuracy_dispersion_m must be greater than or equal "
			+ "to perfect_accuracy_dispersion_m."
		)
	return errors
