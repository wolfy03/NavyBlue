extends RefCounted
class_name ShellRangeTestRunner

# Deprecated: compatibility only. New math-only tests use
# BallisticMathTestRunner, while projectile flight uses the integration scene.


static func evaluate_ranges(
		muzzle_speed: float,
		gravity_mps2: float,
		configured_range_m: float,
		start_height_m: float = 10.0,
		target_height_m: float = 0.0
) -> Array[Dictionary]:
	return BallisticMathTestRunner.evaluate_ranges(
		muzzle_speed,
		gravity_mps2,
		configured_range_m,
		start_height_m,
		target_height_m
	)
