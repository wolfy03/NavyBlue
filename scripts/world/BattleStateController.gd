extends Node
class_name BattleStateController

const REWARD_SYSTEM_SCRIPT := preload("res://scripts/meta/RewardSystem.gd")

signal battle_cleared(stage_id: String)
signal battle_failed(stage_id: String)

var stage_id := ""
var reward_table_id := ""
var battle_active := false
var result_emitted := false
var player_ship: Node
var allies: Array = []
var enemies: Array = []

func start_battle(stage_data: StageData, next_player_ship: Node, next_allies: Array, next_enemies: Array) -> void:
	stage_id = stage_data.id
	reward_table_id = stage_data.reward_table_id
	player_ship = next_player_ship
	allies = next_allies.duplicate()
	enemies = next_enemies.duplicate()
	battle_active = true
	result_emitted = false
	_connect_ship_death(player_ship, Callable(self, "_on_player_died"))
	for enemy in enemies:
		_connect_ship_death(enemy, Callable(self, "_on_enemy_died").bind(enemy))
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").battle_started.emit(stage_id)
	call_deferred("_check_result")

func stop_battle() -> void:
	battle_active = false

func _connect_ship_death(ship: Node, callback: Callable) -> void:
	if ship == null:
		return
	var health := ship.get_node_or_null("ShipHealth")
	if health == null or not health.has_signal("died"):
		return
	if not health.is_connected("died", callback):
		health.connect("died", callback)

func _on_player_died() -> void:
	_fail_battle()

func _on_enemy_died(_enemy: Node) -> void:
	call_deferred("_check_result")

func _check_result() -> void:
	if not battle_active or result_emitted:
		return
	if not _is_ship_alive(player_ship):
		_fail_battle()
		return
	if _all_enemies_destroyed():
		_clear_battle()

func _all_enemies_destroyed() -> bool:
	for enemy in enemies:
		if _is_ship_alive(enemy):
			return false
	return true

func _is_ship_alive(ship: Node) -> bool:
	if not is_instance_valid(ship):
		return false
	var health := ship.get_node_or_null("ShipHealth")
	if health != null and health.get("current_health") != null:
		return float(health.get("current_health")) > 0.0
	return not ship.is_queued_for_deletion()

func _clear_battle() -> void:
	if result_emitted:
		return
	result_emitted = true
	battle_active = false
	var rewards := REWARD_SYSTEM_SCRIPT.new().roll_upgrade_rewards(3, reward_table_id)
	if has_node("/root/RunManager"):
		var run_manager = get_node("/root/RunManager")
		run_manager.capture_player_ship(player_ship)
		run_manager.set_pending_rewards(rewards)
		run_manager.save_current_run()
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").battle_cleared.emit(stage_id)
	battle_cleared.emit(stage_id)
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_reward()
	# TODO: Connect this to SceneLoader.load_reward() when reward scene exists.

func _fail_battle() -> void:
	if result_emitted:
		return
	result_emitted = true
	battle_active = false
	if has_node("/root/RunManager"):
		var run_manager = get_node("/root/RunManager")
		run_manager.finish_run({
			"success": false,
			"stage_id": stage_id,
		})
		run_manager.clear_saved_run()
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").battle_failed.emit(stage_id)
	battle_failed.emit(stage_id)
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_game_over()
