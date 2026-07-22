extends Node
class_name RewardSystem

const UPGRADE_DATA_SCRIPT := preload("res://scripts/meta/UpgradeData.gd")

func roll_rewards() -> Array:
	return roll_upgrade_rewards(3, "")

func roll_upgrade_rewards(count: int = 3, reward_table_id: String = "") -> Array:
	var definitions := _upgrade_definitions(reward_table_id)
	var ids := definitions.keys()
	ids.shuffle()
	var rewards: Array = []
	for index in range(mini(count, ids.size())):
		var upgrade_id := str(ids[index])
		rewards.append(_upgrade_to_dictionary(_make_upgrade(upgrade_id, definitions[upgrade_id])))
	return rewards

func get_upgrade(upgrade_id: String) -> Resource:
	var definitions := _upgrade_definitions("")
	if not definitions.has(upgrade_id):
		return null
	return _make_upgrade(upgrade_id, definitions[upgrade_id])

func _make_upgrade(id: String, definition: Dictionary) -> Resource:
	var upgrade: Resource = UPGRADE_DATA_SCRIPT.new()
	upgrade.set("id", id)
	upgrade.set("display_name", definition.get("display_name", id))
	upgrade.set("description", definition.get("description", ""))
	upgrade.set("upgrade_type", definition.get("upgrade_type", "add"))
	upgrade.set("value", float(definition.get("value", 0.0)))
	upgrade.set("target_stat", definition.get("target_stat", ""))
	return upgrade

func _upgrade_to_dictionary(upgrade: Resource) -> Dictionary:
	return {
		"id": str(upgrade.get("id")),
		"display_name": str(upgrade.get("display_name")),
		"description": str(upgrade.get("description")),
		"upgrade_type": str(upgrade.get("upgrade_type")),
		"value": float(upgrade.get("value")),
		"target_stat": str(upgrade.get("target_stat")),
	}

func _upgrade_definitions(_reward_table_id: String) -> Dictionary:
	return {
		"hull_reinforcement_1": {
			"display_name": "Hull Reinforcement I",
			"description": "Increase ship health.",
			"upgrade_type": "multiply",
			"value": 1.12,
			"target_stat": "max_health",
		},
		"engine_tuning_1": {
			"display_name": "Engine Tuning I",
			"description": "Increase maximum forward speed.",
			"upgrade_type": "multiply",
			"value": 1.08,
			"target_stat": "max_forward_speed",
		},
		"reload_drill_1": {
			"display_name": "Reload Drill I",
			"description": "Reduce reload time.",
			"upgrade_type": "multiply",
			"value": 0.92,
			"target_stat": "reload_seconds",
		},
		"fire_control_1": {
			"display_name": "Fire Control I",
			"description": "Increase shell muzzle velocity.",
			"upgrade_type": "multiply",
			"value": 1.06,
			"target_stat": "shell_muzzle_velocity",
		},
	}
