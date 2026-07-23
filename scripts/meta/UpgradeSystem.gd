extends Node
class_name UpgradeSystem

const REWARD_SYSTEM_SCRIPT := preload("res://scripts/meta/RewardSystem.gd")
const UPGRADE_DATA_SCRIPT := preload("res://scripts/data/UpgradeData.gd")

func apply_upgrade(_upgrade: Resource, _target) -> void:
	pass

func apply_upgrades_to_ship(ship, upgrades: Array) -> void:
	if ship == null:
		return
	ship.set_meta("active_upgrades", upgrades.duplicate(true))
	var ship_data := ship.get("ship_data") as Resource
	if ship_data == null:
		return
	var modified_data := ship_data.duplicate(true)
	_apply_stat_if_present(modified_data, "max_forward_speed", upgrades)
	_apply_stat_if_present(modified_data, "max_speed_mps", upgrades)
	_apply_stat_if_present(modified_data, "reload_seconds", upgrades)
	_apply_stat_if_present(modified_data, "shell_muzzle_velocity", upgrades)
	_apply_stat_if_present(modified_data, "turn_rate_degrees", upgrades)
	_apply_stat_if_present(modified_data, "max_turn_rate_deg_sec", upgrades)
	var defense_stats: ShipDefenseStats = modified_data.get("defense_stats")
	if defense_stats != null:
		defense_stats = defense_stats.duplicate(true) as ShipDefenseStats
		defense_stats.max_hp = get_modified_stat(defense_stats.max_hp, "max_health", upgrades)
		defense_stats.current_hp = minf(defense_stats.current_hp, defense_stats.max_hp)
		modified_data.set("defense_stats", defense_stats)
	ship.set("ship_data", modified_data)
	if ship is Node and ship.has_node("ShipMovement"):
		var movement = ship.get_node("ShipMovement")
		movement.set("ship_data", modified_data)
	if ship is Node and ship.has_node("ShipCombat"):
		_apply_weapon_stats_to_turrets(ship.get_node("ShipCombat"), modified_data)
	if ship is Node and ship.has_node("ShipHealth") and defense_stats != null:
		var health = ship.get_node("ShipHealth")
		if health.has_method("setup"):
			health.setup(defense_stats)
	# TODO: Reinitialize movement and turret components when upgrades become selectable in active battle.

func get_modified_stat(base_value: float, stat_name: String, upgrades: Array) -> float:
	var result := base_value
	for upgrade_value in upgrades:
		var upgrade := _resolve_upgrade(upgrade_value)
		if upgrade == null or upgrade.target_stat != stat_name:
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
	return REWARD_SYSTEM_SCRIPT.new().get_upgrade(upgrade_id)

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

func _apply_stat_if_present(data: Resource, stat_name: String, upgrades: Array) -> void:
	if data == null:
		return
	var value: Variant = data.get(stat_name)
	if value == null:
		return
	data.set(stat_name, get_modified_stat(float(value), stat_name, upgrades))

func _apply_weapon_stats_to_turrets(combat: Node, ship_data: Resource) -> void:
	if combat == null or ship_data == null:
		return
	var turrets: Array = combat.get("turrets") if combat.get("turrets") is Array else []
	for turret in turrets:
		if not is_instance_valid(turret):
			continue
		if turret.get("muzzle_velocity") != null:
			turret.set("muzzle_velocity", ship_data.get("shell_muzzle_velocity"))
		if turret.get("reload_seconds") != null:
			turret.set("reload_seconds", ship_data.get("reload_seconds"))
