extends RefCounted
class_name ShellDamageCalculator


static func resolve(hit_info: HitInfo) -> DamageResult:
	var result := DamageResult.new()
	result.hit_info = hit_info
	result.target_ship = hit_info.target_ship if hit_info != null else null
	if hit_info == null or hit_info.shell_stats == null:
		push_warning("Shell damage calculation requires shell statistics.")
		return result
	if not is_instance_valid(hit_info.target_ship) \
			or not hit_info.target_ship.has_method(&"get_defense_stats"):
		push_warning("Shell damage target is invalid.")
		return result
	var defense_variant: Variant = hit_info.target_ship.call(&"get_defense_stats")
	if not defense_variant is ShipDefenseStats:
		push_warning("Shell damage target returned invalid defense stats.")
		return result
	var defense_stats := defense_variant as ShipDefenseStats
	var armor := defense_stats.get_armor_by_part(hit_info.armor_part)
	var penetration_check := PenetrationResolver.resolve(
		hit_info.shell_stats,
		armor,
		hit_info.shell_direction,
		hit_info.hit_normal
	)
	result.damage_type = hit_info.damage_type
	result.penetration_result = penetration_check.result
	result.hit_outcome = HitOutcome.from_penetration_result(
		penetration_check.result
	)
	result.impact_angle_degrees = penetration_check.impact_angle_degrees
	result.armor = penetration_check.armor
	result.effective_armor = penetration_check.effective_armor
	result.raw_damage = calculate_damage(
		hit_info.shell_stats,
		penetration_check.result
	)
	if not hit_info.target_ship.has_method(&"apply_damage_result") \
			and not hit_info.target_ship.has_method(&"apply_damage"):
		push_warning("Shell damage target does not expose a damage entry point.")
		return result
	var applied: Variant
	if hit_info.target_ship.has_method(&"apply_damage_result"):
		applied = hit_info.target_ship.call(&"apply_damage_result", result)
	else:
		applied = hit_info.target_ship.call(
			&"apply_damage",
			result.raw_damage,
			penetration_check.result,
			hit_info
		)
	result.applied_damage = float(applied) if applied != null else result.raw_damage
	result.final_damage = result.applied_damage
	result.resolved = true
	return result


static func calculate_damage(
		shell_stats: ShellStats,
		penetration_result: int
) -> float:
	if shell_stats == null:
		return 0.0
	var base_damage := maxf(shell_stats.base_damage, 0.0)
	match shell_stats.shell_type:
		ShellStats.ShellType.AP:
			return _calculate_ap_damage(
				shell_stats,
				penetration_result,
				base_damage
			)
		ShellStats.ShellType.HE:
			return _calculate_he_damage(
				shell_stats,
				penetration_result,
				base_damage
			)
	return 0.0


static func _calculate_ap_damage(
		shell_stats: ShellStats,
		penetration_result: int,
		base_damage: float
) -> float:
	match penetration_result:
		PenetrationResolver.Result.PENETRATED:
			return base_damage * maxf(
				shell_stats.penetration_damage_multiplier,
				0.0
			)
		PenetrationResolver.Result.NON_PENETRATED:
			return base_damage * maxf(
				shell_stats.non_penetration_damage_multiplier,
				0.0
			)
		PenetrationResolver.Result.RICOCHET:
			return base_damage * maxf(
				shell_stats.ricochet_damage_multiplier,
				0.0
			)
	return 0.0


static func _calculate_he_damage(
		shell_stats: ShellStats,
		penetration_result: int,
		base_damage: float
) -> float:
	var explosion_damage := maxf(shell_stats.explosion_damage, 0.0)
	match penetration_result:
		PenetrationResolver.Result.PENETRATED:
			return base_damage * maxf(
				shell_stats.penetration_damage_multiplier,
				0.0
			) + explosion_damage
		PenetrationResolver.Result.NON_PENETRATED:
			return base_damage * maxf(
				shell_stats.non_penetration_damage_multiplier,
				0.0
			) + explosion_damage
		PenetrationResolver.Result.RICOCHET:
			return base_damage * maxf(
				shell_stats.ricochet_damage_multiplier,
				0.0
			) + explosion_damage * 0.5
	return 0.0
