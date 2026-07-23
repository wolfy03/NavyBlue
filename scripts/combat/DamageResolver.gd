class_name DamageResolver
extends RefCounted


static func resolve_hit(hit_info: HitInfo) -> DamageResult:
	if hit_info == null:
		push_warning("DamageResolver received null hit information.")
		return DamageResult.new()
	match hit_info.damage_type:
		DamageType.Type.SHELL_AP, DamageType.Type.SHELL_HE:
			return ShellDamageCalculator.resolve(hit_info)
		DamageType.Type.TORPEDO:
			return TorpedoDamageCalculator.resolve(hit_info)
		_:
			return _resolve_direct_damage(hit_info)


static func calculate_shell_damage(
		shell_stats: ShellStats,
		penetration_result: int
) -> float:
	return ShellDamageCalculator.calculate_damage(
		shell_stats,
		penetration_result
	)


static func _resolve_direct_damage(hit_info: HitInfo) -> DamageResult:
	var result := DamageResult.new()
	result.hit_info = hit_info
	result.target_ship = hit_info.target_ship
	if not is_instance_valid(hit_info.target_ship) \
			or not hit_info.target_ship.has_method(&"apply_damage"):
		return result
	var raw_damage := float(hit_info.projectile_info.get("damage", 0.0))
	var applied: Variant = hit_info.target_ship.call(
		&"apply_damage",
		raw_damage,
		PenetrationResolver.Result.NON_PENETRATED,
		hit_info
	)
	result.raw_damage = raw_damage
	result.applied_damage = float(applied) if applied != null else raw_damage
	result.final_damage = result.applied_damage
	result.resolved = true
	return result
