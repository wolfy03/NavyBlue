extends RefCounted
class_name TorpedoDamageCalculator


static func resolve(hit_info: HitInfo) -> DamageResult:
	var result := DamageResult.new()
	result.hit_info = hit_info
	result.target_ship = hit_info.target_ship if hit_info != null else null
	if hit_info == null or hit_info.torpedo_data == null \
			or not is_instance_valid(hit_info.target_ship):
		push_warning("Torpedo damage calculation received incomplete hit data.")
		return result
	if not hit_info.target_ship.has_method(&"apply_damage_result") \
			and not hit_info.target_ship.has_method(&"apply_damage"):
		push_warning("Torpedo target does not expose a damage entry point.")
		return result
	var data := hit_info.torpedo_data
	var raw_damage := (data.direct_damage + data.explosion_damage) \
		* _get_section_multiplier(hit_info.armor_part) \
		* maxf(
			float(hit_info.projectile_info.get("damage_multiplier", 1.0)),
			0.0
		)
	result.damage_type = DamageType.Type.TORPEDO
	result.hit_outcome = HitOutcome.Type.TORPEDO_HIT
	result.raw_damage = raw_damage
	var applied: Variant
	if hit_info.target_ship.has_method(&"apply_damage_result"):
		applied = hit_info.target_ship.call(&"apply_damage_result", result)
	else:
		# Legacy targets still receive a neutral compatibility value. It is not
		# interpreted as an AP penetration result by the returned DamageResult.
		applied = hit_info.target_ship.call(
			&"apply_damage",
			raw_damage,
			PenetrationResolver.Result.NON_PENETRATED,
			hit_info
		)
	result.applied_damage = float(applied) if applied != null else raw_damage
	result.final_damage = result.applied_damage
	result.resolved = true
	var flooding_chance := clampf(
		data.flooding_chance
		+ float(hit_info.projectile_info.get("flooding_chance_bonus", 0.0)),
		0.0,
		1.0
	)
	if randf() <= flooding_chance \
			and hit_info.target_ship.has_method(&"apply_flooding"):
		result.flooding_triggered = true
		hit_info.target_ship.call(
			&"apply_flooding",
			data.flooding_duration_seconds,
			data.flooding_damage_per_second,
			hit_info
		)
	return result


static func _get_section_multiplier(part: ArmorPart.Type) -> float:
	match part:
		ArmorPart.Type.BOW:
			return 0.85
		ArmorPart.Type.STERN:
			return 1.1
		ArmorPart.Type.BELT:
			return 1.0
	return 1.0
