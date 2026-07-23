extends Node
class_name RewardSystem

const UPGRADE_PATHS := {
	"hull_reinforcement_1": "res://resources/upgrades/hull_reinforcement_1.tres",
	"engine_tuning_1": "res://resources/upgrades/engine_tuning_1.tres",
	"acceleration_tuning_1": "res://resources/upgrades/acceleration_tuning_1.tres",
	"steering_gear_1": "res://resources/upgrades/steering_gear_1.tres",
	"reload_drill_1": "res://resources/upgrades/reload_drill_1.tres",
	"fire_control_1": "res://resources/upgrades/fire_control_1.tres",
}

func roll_rewards() -> Array:
	return roll_upgrade_rewards(3, "")

func roll_upgrade_rewards(count: int = 3, _reward_table_id: String = "") -> Array:
	var ids := UPGRADE_PATHS.keys()
	ids.shuffle()
	var rewards: Array = []
	for index in range(mini(maxi(count, 0), ids.size())):
		var upgrade := get_upgrade(str(ids[index]))
		if upgrade != null:
			rewards.append(upgrade)
	return rewards

func get_upgrade(upgrade_id: String) -> UpgradeData:
	var path := str(UPGRADE_PATHS.get(upgrade_id, ""))
	if path.is_empty():
		return null
	var upgrade := load(path) as UpgradeData
	if upgrade == null:
		push_warning("Failed to load upgrade data: %s" % path)
	return upgrade

func get_reward_ids(rewards: Array) -> Array[String]:
	var ids: Array[String] = []
	for reward in rewards:
		if reward is UpgradeData and not reward.id.is_empty():
			ids.append(reward.id)
		elif reward is String and not reward.is_empty():
			ids.append(reward)
		elif reward is Dictionary:
			var reward_id := str(reward.get("id", ""))
			if not reward_id.is_empty():
				ids.append(reward_id)
	return ids

func select_reward(upgrade_id: String) -> bool:
	if get_upgrade(upgrade_id) == null:
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
