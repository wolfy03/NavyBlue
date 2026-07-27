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
var _death_connections: Array[Dictionary] = []

func start_battle(stage_data: StageData, next_player_ship: Node, next_allies: Array, next_enemies: Array) -> void:
	stop_battle()
	result_emitted = false
	if stage_data == null:
		push_warning("BattleStateController.start_battle() received null StageData.")
		_fail_battle()
		return
	stage_id = stage_data.id
	reward_table_id = stage_data.reward_table_id
	player_ship = next_player_ship
	allies = next_allies.duplicate()
	enemies = []
	for enemy in next_enemies:
		if _is_ship_alive(enemy):
			enemies.append(enemy)
	if not _is_ship_alive(player_ship):
		push_warning("BattleStateController cannot start battle without a live player ship.")
		_fail_battle()
		return
	battle_active = true
	_connect_ship_death(player_ship, Callable(self, "_on_player_died"))
	for enemy in enemies:
		_connect_ship_death(enemy, Callable(self, "_on_enemy_died").bind(enemy))
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").battle_started.emit(stage_id)
	call_deferred("_check_result")

func stop_battle() -> void:
	battle_active = false
	for connection in _death_connections:
		var health_value: Variant = connection.get("health")
		var callback: Callable = connection.get("callback")
		if health_value == null or not is_instance_valid(health_value):
			continue
		var health := health_value as Node
		if health != null and health.is_connected("died", callback):
			health.disconnect("died", callback)
	_death_connections.clear()

func _connect_ship_death(ship_value: Variant, callback: Callable) -> void:
	if ship_value == null or not is_instance_valid(ship_value):
		return
	var ship := ship_value as Node
	if ship == null:
		return
	var health := ship.get_node_or_null("ShipHealth")
	if health == null or not health.has_signal("died"):
		return
	if not health.is_connected("died", callback):
		health.connect("died", callback)
		_death_connections.append({
			"health": health,
			"callback": callback,
		})

func _on_player_died() -> void:
	_fail_battle()

func _on_enemy_died(enemy: Variant) -> void:
	enemies.erase(enemy)
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
	for index in range(enemies.size() - 1, -1, -1):
		var enemy: Variant = enemies[index]
		if _is_ship_alive(enemy):
			return false
		enemies.remove_at(index)
	return true

func _is_ship_alive(ship: Variant) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var ship_node := ship as Node
	if ship_node == null:
		return false
	var health := ship_node.get_node_or_null("ShipHealth")
	if health != null and health.get("current_health") != null:
		return float(health.get("current_health")) > 0.0
	return not ship_node.is_queued_for_deletion()

func _clear_battle() -> void:
	if result_emitted:
		return
	result_emitted = true
	stop_battle()
	_resolve_player_components(true)
	_clear_active_projectiles()
	var reward_system := REWARD_SYSTEM_SCRIPT.new()
	var rewards: Array = reward_system.roll_upgrade_rewards(3, reward_table_id)
	var reward_ids: Array[String] = reward_system.get_reward_ids(rewards)
	reward_system.free()
	if has_node("/root/RunManager"):
		var run_manager = get_node("/root/RunManager")
		run_manager.capture_player_ship(player_ship)
		run_manager.set_pending_rewards(reward_ids)
		var save_error: Error = run_manager.save_current_run()
		if save_error != OK:
			push_warning("Failed to save run after battle clear: %s" % save_error)
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
	stop_battle()
	_resolve_player_components(false)
	_clear_active_projectiles()
	if has_node("/root/RunManager"):
		var run_manager = get_node("/root/RunManager")
		run_manager.finish_run({
			"success": false,
			"stage_id": stage_id,
		})
		var clear_error: Error = run_manager.clear_saved_run()
		if clear_error != OK:
			push_warning("Failed to clear saved run after battle failure: %s" % clear_error)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").battle_failed.emit(stage_id)
	battle_failed.emit(stage_id)
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_game_over()


func _resolve_player_components(success: bool) -> void:
	if player_ship == null or not is_instance_valid(player_ship):
		return
	if player_ship.has_method(&"resolve_battle_end"):
		player_ship.call(&"resolve_battle_end", success)


func _clear_active_projectiles() -> void:
	var projectiles := get_parent().get_node_or_null("Projectiles") \
		if get_parent() != null else null
	if projectiles == null:
		return
	for child in projectiles.get_children():
		if child.has_method(&"despawn"):
			child.call(&"despawn")
		else:
			child.queue_free()
