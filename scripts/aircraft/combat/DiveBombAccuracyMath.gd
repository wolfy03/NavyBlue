extends RefCounted
class_name DiveBombAccuracyMath
## Pure deterministic dispersion math shared by profile and compatibility API.


static func resolve_offset(
		accuracy: float,
		minimum_radius_m: float,
		maximum_radius_m: float,
		deterministic_seed: int
) -> Vector3:
	var radius := lerpf(
		maxf(maximum_radius_m, 0.0),
		maxf(minimum_radius_m, 0.0),
		clampf(accuracy, 0.0, 1.0)
	)
	if radius <= 0.001:
		return Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = deterministic_seed
	var angle := rng.randf_range(0.0, TAU)
	var distance := radius * sqrt(rng.randf())
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
