class_name DamageResolver
extends RefCounted


static func resolve_hit(hit_info: HitInfo) -> DamageResult:
	var damage_result := DamageResult.new()
	damage_result.hit_info = hit_info
	if hit_info == null or hit_info.shell_stats == null:
		push_warning("DamageResolver received incomplete hit information.")
		return damage_result
	if not is_instance_valid(hit_info.target_ship):
		push_warning("DamageResolver received an invalid target ship.")
		return damage_result
	if not hit_info.target_ship.has_method(&"get_defense_stats"):
		push_warning("Damage target does not expose get_defense_stats().")
		return damage_result

	var defense_variant: Variant = hit_info.target_ship.call(&"get_defense_stats")
	if not defense_variant is ShipDefenseStats:
		push_warning("Damage target returned invalid defense stats.")
		return damage_result
	var defense_stats := defense_variant as ShipDefenseStats
	var armor: float = defense_stats.get_armor_by_part(hit_info.armor_part)
	var penetration_check := PenetrationResolver.resolve(
		hit_info.shell_stats,
		armor,
		hit_info.shell_direction,
		hit_info.hit_normal
	)

	damage_result.penetration_result = penetration_check.result
	damage_result.impact_angle_degrees = penetration_check.impact_angle_degrees
	damage_result.armor = penetration_check.armor
	damage_result.effective_armor = penetration_check.effective_armor
	damage_result.raw_damage = calculate_shell_damage(hit_info.shell_stats, penetration_check.result)

	if not hit_info.target_ship.has_method(&"apply_damage"):
		push_warning("Damage target does not expose apply_damage().")
		return damage_result
	var applied_variant: Variant = hit_info.target_ship.call(
		&"apply_damage",
		damage_result.raw_damage,
		penetration_check.result,
		hit_info
	)
	damage_result.applied_damage = float(applied_variant) if applied_variant != null else damage_result.raw_damage
	damage_result.resolved = true
	return damage_result


static func calculate_shell_damage(shell_stats: ShellStats, penetration_result: int) -> float:
	if shell_stats == null:
		return 0.0
	var base_damage: float = maxf(shell_stats.base_damage, 0.0)
	match shell_stats.shell_type:
		ShellStats.ShellType.AP:
			return _calculate_ap_damage(shell_stats, penetration_result, base_damage)
		ShellStats.ShellType.HE:
			return _calculate_he_damage(shell_stats, penetration_result, base_damage)
	return 0.0


static func _calculate_ap_damage(shell_stats: ShellStats, penetration_result: int, base_damage: float) -> float:
	match penetration_result:
		PenetrationResolver.Result.PENETRATED:
			return base_damage * maxf(shell_stats.penetration_damage_multiplier, 0.0)
		PenetrationResolver.Result.NON_PENETRATED:
			return base_damage * maxf(shell_stats.non_penetration_damage_multiplier, 0.0)
		PenetrationResolver.Result.RICOCHET:
			return base_damage * maxf(shell_stats.ricochet_damage_multiplier, 0.0)
	return 0.0


static func _calculate_he_damage(shell_stats: ShellStats, penetration_result: int, base_damage: float) -> float:
	var explosion_damage: float = maxf(shell_stats.explosion_damage, 0.0)
	match penetration_result:
		PenetrationResolver.Result.PENETRATED:
			return base_damage * maxf(shell_stats.penetration_damage_multiplier, 0.0) + explosion_damage
		PenetrationResolver.Result.NON_PENETRATED:
			return base_damage * maxf(shell_stats.non_penetration_damage_multiplier, 0.0) + explosion_damage
		PenetrationResolver.Result.RICOCHET:
			return base_damage * maxf(shell_stats.ricochet_damage_multiplier, 0.0) + explosion_damage * 0.5
	return 0.0
