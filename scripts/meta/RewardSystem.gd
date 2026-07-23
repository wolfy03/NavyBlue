extends Node
class_name RewardSystem

const UPGRADE_DATA_SCRIPT := preload("res://scripts/data/UpgradeData.gd")

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

func get_upgrade(upgrade_id: String) -> UpgradeData:
	var definitions := _upgrade_definitions("")
	if not definitions.has(upgrade_id):
		return null
	return _make_upgrade(upgrade_id, definitions[upgrade_id])

func select_reward(upgrade_id: String) -> bool:
	if upgrade_id.is_empty():
		return false
	if has_node("/root/RunManager"):
		var run_manager = get_node("/root/RunManager")
		run_manager.add_upgrade(upgrade_id)
		run_manager.clear_pending_rewards()
		var save_error: Error = run_manager.save_current_run()
		if save_error != OK:
			push_warning("Failed to save run after selecting reward '%s': %s" % [upgrade_id, save_error])
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").reward_selected.emit(upgrade_id)
	# TODO: Continue to the next stage selection flow when the reward UI exists.
	return true

func _make_upgrade(id: String, definition: Dictionary) -> UpgradeData:
	var upgrade := UPGRADE_DATA_SCRIPT.new() as UpgradeData
	upgrade.id = id
	upgrade.display_name = definition.get("display_name", id)
	upgrade.description = definition.get("description", "")
	upgrade.upgrade_type = definition.get("upgrade_type", "multiply")
	upgrade.value = float(definition.get("value", 0.0))
	upgrade.target_stat = definition.get("target_stat", "")
	upgrade.is_percent = bool(definition.get("is_percent", false))
	upgrade.modifiers = definition.get("modifiers", {})
	return upgrade

func _upgrade_to_dictionary(upgrade: UpgradeData) -> Dictionary:
	return {
		"id": upgrade.id,
		"display_name": upgrade.display_name,
		"description": upgrade.description,
		"upgrade_type": upgrade.upgrade_type,
		"value": upgrade.value,
		"target_stat": upgrade.target_stat,
		"is_percent": upgrade.is_percent,
		"modifiers": upgrade.modifiers.duplicate(true),
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
