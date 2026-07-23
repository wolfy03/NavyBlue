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
	if not hit_info.target_ship.has_method(&"apply_damage"):
		push_warning("Torpedo target does not expose apply_damage().")
		return result
	var data := hit_info.torpedo_data
	var raw_damage := (data.direct_damage + data.explosion_damage) \
		* _get_section_multiplier(hit_info.armor_part)
	var applied: Variant = hit_info.target_ship.call(
		&"apply_damage",
		raw_damage,
		PenetrationResolver.Result.PENETRATED,
		hit_info
	)
	result.penetration_result = PenetrationResolver.Result.PENETRATED
	result.raw_damage = raw_damage
	result.applied_damage = float(applied) if applied != null else raw_damage
	result.final_damage = result.applied_damage
	result.resolved = true
	if randf() <= clampf(data.flooding_chance, 0.0, 1.0) \
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
