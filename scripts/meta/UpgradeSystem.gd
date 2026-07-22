extends Node
class_name UpgradeSystem

const REWARD_SYSTEM_SCRIPT := preload("res://scripts/meta/RewardSystem.gd")
const UPGRADE_DATA_SCRIPT := preload("res://scripts/meta/UpgradeData.gd")

func apply_upgrade(_upgrade: Resource, _target) -> void:
	pass

func apply_upgrades_to_ship(ship, upgrades: Array) -> void:
	if ship == null:
		return
	ship.set_meta("active_upgrades", upgrades.duplicate(true))
	# TODO: Rebuild ship data and component stats from modified values when the stat model stabilizes.

func get_modified_stat(base_value: float, stat_name: String, upgrades: Array) -> float:
	var result := base_value
	for upgrade_value in upgrades:
		var upgrade := _resolve_upgrade(upgrade_value)
		if upgrade == null or str(upgrade.get("target_stat")) != stat_name:
			continue
		match str(upgrade.get("upgrade_type")):
			"add":
				result += float(upgrade.get("value"))
			"multiply":
				result *= float(upgrade.get("value"))
			"percent_add":
				result *= 1.0 + float(upgrade.get("value"))
	return result

func _resolve_upgrade(value) -> Resource:
	if value is Resource:
		return value
	if value is String:
		return REWARD_SYSTEM_SCRIPT.new().get_upgrade(value)
	if value is Dictionary:
		var upgrade: Resource = UPGRADE_DATA_SCRIPT.new()
		var upgrade_id := str(value.get("id", ""))
		upgrade.set("id", upgrade_id)
		upgrade.set("display_name", str(value.get("display_name", upgrade_id)))
		upgrade.set("description", str(value.get("description", "")))
		upgrade.set("upgrade_type", str(value.get("upgrade_type", "add")))
		upgrade.set("value", float(value.get("value", 0.0)))
		upgrade.set("target_stat", str(value.get("target_stat", "")))
		return upgrade
	return null
