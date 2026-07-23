extends RefCounted
class_name WeaponRuntimeStats

var reload_multiplier := 1.0
var damage_multiplier := 1.0
var range_multiplier := 1.0
var projectile_speed_multiplier := 1.0
var projectile_count_bonus := 0
var traverse_speed_multiplier := 1.0
var flooding_chance_bonus := 0.0


func reset() -> void:
	reload_multiplier = 1.0
	damage_multiplier = 1.0
	range_multiplier = 1.0
	projectile_speed_multiplier = 1.0
	projectile_count_bonus = 0
	traverse_speed_multiplier = 1.0
	flooding_chance_bonus = 0.0


func duplicate_stats() -> WeaponRuntimeStats:
	return WeaponRuntimeStats.from_dictionary(to_dictionary())


func to_dictionary() -> Dictionary:
	return {
		"reload_multiplier": reload_multiplier,
		"damage_multiplier": damage_multiplier,
		"range_multiplier": range_multiplier,
		"projectile_speed_multiplier": projectile_speed_multiplier,
		"projectile_count_bonus": projectile_count_bonus,
		"traverse_speed_multiplier": traverse_speed_multiplier,
		"flooding_chance_bonus": flooding_chance_bonus,
	}


static func from_dictionary(data: Dictionary) -> WeaponRuntimeStats:
	var stats := WeaponRuntimeStats.new()
	stats.reload_multiplier = float(data.get("reload_multiplier", 1.0))
	stats.damage_multiplier = float(data.get("damage_multiplier", 1.0))
	stats.range_multiplier = float(data.get("range_multiplier", 1.0))
	stats.projectile_speed_multiplier = float(
		data.get("projectile_speed_multiplier", 1.0)
	)
	stats.projectile_count_bonus = int(data.get("projectile_count_bonus", 0))
	stats.traverse_speed_multiplier = float(
		data.get("traverse_speed_multiplier", 1.0)
	)
	stats.flooding_chance_bonus = float(
		data.get("flooding_chance_bonus", 0.0)
	)
	return stats
