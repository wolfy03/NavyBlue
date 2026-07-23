extends Node
class_name UpgradeSystem

const REWARD_SYSTEM_SCRIPT := preload("res://scripts/meta/RewardSystem.gd")
const UPGRADE_DATA_SCRIPT := preload("res://scripts/data/UpgradeData.gd")

const SUPPORTED_SHIP_STATS: Array[StringName] = [
	&"max_speed_mps",
	&"cruise_speed_mps",
	&"max_reverse_speed_mps",
	&"acceleration_mps2",
	&"deceleration_mps2",
	&"max_turn_rate_deg_sec",
	&"turn_acceleration_deg_sec2",
	&"arrival_slowdown_distance_m",
	&"minimum_turning_speed_mps",
	&"navigation_safety_radius_m",
	&"reload_seconds",
	&"shell_muzzle_velocity",
]


func apply_upgrade(upgrade: Resource, target) -> void:
	if upgrade == null or target == null:
		return
	var active_upgrades: Array = []
	if target.has_meta(&"active_upgrades"):
		var existing: Variant = target.get_meta(&"active_upgrades")
		if existing is Array:
			active_upgrades = existing.duplicate(true)
	active_upgrades.append(upgrade)
	apply_upgrades_to_ship(target, active_upgrades)


func apply_upgrades_to_ship(ship, upgrades: Array) -> void:
	if ship == null:
		return
	ship.set_meta(&"active_upgrades", upgrades.duplicate(true))
	var current_ship_data := ship.get(&"ship_data") as ShipData
	if current_ship_data == null:
		return
	if not ship.has_meta(&"base_ship_data"):
		ship.set_meta(&"base_ship_data", current_ship_data.duplicate(true))
	var base_ship_data := ship.get_meta(&"base_ship_data") as ShipData
	if base_ship_data == null:
		return
	var modified_data := base_ship_data.duplicate(true) as ShipData
	for stat_name in SUPPORTED_SHIP_STATS:
		if _resource_has_property(modified_data, stat_name):
			_apply_stat(modified_data, stat_name, upgrades)

	var defense_stats := modified_data.defense_stats
	if defense_stats != null:
		defense_stats = defense_stats.duplicate(true) as ShipDefenseStats
		defense_stats.max_hp = get_modified_stat(defense_stats.max_hp, &"max_health", upgrades)
		defense_stats.current_hp = minf(defense_stats.current_hp, defense_stats.max_hp)
		modified_data.defense_stats = defense_stats
	ship.set(&"ship_data", modified_data)

	if ship is Node and ship.has_node("ShipMovement"):
		ship.get_node("ShipMovement").set(&"ship_data", modified_data)
	if ship is Node and ship.has_node("ShipCombat"):
		_apply_weapon_stats_to_turrets(ship.get_node("ShipCombat"), modified_data)
	if ship is Node and ship.has_node("ThreatTargetingComponent"):
		var targeting: Node = ship.get_node("ThreatTargetingComponent")
		if targeting.has_method(&"set_role_profile"):
			targeting.call(&"set_role_profile", modified_data.ai_role_profile)
	if ship is Node and ship.has_node("ShipAI"):
		var ship_ai: Node = ship.get_node("ShipAI")
		if ship_ai.has_method(&"setup"):
			ship_ai.call(&"setup", ship, modified_data)
	if ship is Node and ship.has_node("ShipHealth") and defense_stats != null:
		var health: Node = ship.get_node("ShipHealth")
		if health.has_method(&"setup"):
			health.call(&"setup", defense_stats)


func get_modified_stat(base_value: float, stat_name: StringName, upgrades: Array) -> float:
	var result := base_value
	for upgrade_value in upgrades:
		var upgrade := _resolve_upgrade(upgrade_value)
		if upgrade == null or StringName(upgrade.target_stat) != stat_name:
			continue
		match upgrade.upgrade_type:
			"add":
				result += upgrade.value
			"multiply":
				result *= upgrade.value
			"percent_add":
				result *= 1.0 + upgrade.value
			_:
				result = result * upgrade.value if upgrade.is_percent else result + upgrade.value
	return result


func find_upgrade(upgrade_id: String) -> UpgradeData:
	var reward_system := REWARD_SYSTEM_SCRIPT.new()
	var upgrade := reward_system.get_upgrade(upgrade_id)
	reward_system.free()
	return upgrade


func _resolve_upgrade(value) -> UpgradeData:
	if value is UpgradeData:
		return value
	if value is String:
		return find_upgrade(value)
	if value is Dictionary:
		var upgrade := UPGRADE_DATA_SCRIPT.new() as UpgradeData
		var upgrade_id := str(value.get("id", ""))
		upgrade.id = upgrade_id
		upgrade.display_name = str(value.get("display_name", upgrade_id))
		upgrade.description = str(value.get("description", ""))
		upgrade.upgrade_type = str(value.get("upgrade_type", "multiply"))
		upgrade.value = float(value.get("value", 0.0))
		upgrade.target_stat = str(value.get("target_stat", ""))
		upgrade.is_percent = bool(value.get("is_percent", false))
		upgrade.modifiers = value.get("modifiers", {})
		return upgrade
	return null


func _apply_stat(data: Resource, stat_name: StringName, upgrades: Array) -> void:
	var value: Variant = data.get(stat_name)
	if value is float or value is int:
		data.set(stat_name, get_modified_stat(float(value), stat_name, upgrades))


func _resource_has_property(data: Resource, property_name: StringName) -> bool:
	for property_info in data.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true
	return false


func _apply_weapon_stats_to_turrets(combat: Node, ship_data: ShipData) -> void:
	if combat == null or ship_data == null:
		return
	var turrets: Array = combat.get(&"turrets") if combat.get(&"turrets") is Array else []
	for turret in turrets:
		if not is_instance_valid(turret):
			continue
		turret.set(&"muzzle_velocity", ship_data.shell_muzzle_velocity)
		turret.set(&"reload_seconds", ship_data.reload_seconds)
