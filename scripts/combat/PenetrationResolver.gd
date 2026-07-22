class_name PenetrationResolver
extends RefCounted

enum Result {
	PENETRATED,
	NON_PENETRATED,
	RICOCHET,
}

const MIN_IMPACT_COSINE: float = 0.05


static func resolve(
		shell_stats: ShellStats,
		armor: float,
		shell_direction: Vector3,
		hit_normal: Vector3
) -> PenetrationCheck:
	var check := PenetrationCheck.new()
	check.armor = maxf(armor, 0.0)
	check.impact_cosine = calculate_impact_cosine(shell_direction, hit_normal)
	check.impact_angle_degrees = rad_to_deg(acos(clampf(check.impact_cosine, 0.0, 1.0)))
	check.effective_armor = check.armor / maxf(check.impact_cosine, MIN_IMPACT_COSINE)

	if shell_stats == null:
		check.result = Result.NON_PENETRATED
	elif check.impact_angle_degrees >= clampf(shell_stats.ricochet_angle, 0.0, 90.0):
		check.result = Result.RICOCHET
	elif maxf(shell_stats.penetration, 0.0) >= check.effective_armor:
		check.result = Result.PENETRATED
	else:
		check.result = Result.NON_PENETRATED
	return check


static func calculate_impact_cosine(shell_direction: Vector3, hit_normal: Vector3) -> float:
	var direction := shell_direction.normalized() if shell_direction.length_squared() > 0.000001 else Vector3.DOWN
	var normal := hit_normal.normalized() if hit_normal.length_squared() > 0.000001 else Vector3.UP
	return clampf((-direction).dot(normal), 0.0, 1.0)


static func get_result_name(result: Result) -> StringName:
	match result:
		Result.PENETRATED:
			return &"PENETRATED"
		Result.NON_PENETRATED:
			return &"NON_PENETRATED"
		Result.RICOCHET:
			return &"RICOCHET"
	return &"UNKNOWN"
