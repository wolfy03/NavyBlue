extends Node
class_name BattleStateController

const REWARD_SYSTEM_SCRIPT := preload("res://scripts/meta/RewardSystem.gd")

signal battle_cleared(stage_id: String)
signal battle_failed(stage_id: String)

var stage_id := ""
var reward_table_id := ""
var battle_active := false
var result_emitted := false
var player_ship: ShipUnit
var allies: Array[ShipUnit] = []
var enemies: Array[ShipUnit] = []
var _death_connections: Array[Dictionary] = []
var battle_services: BattleServices


func setup(next_battle_services: BattleServices) -> void:
	battle_services = next_battle_services


func start_battle(
		stage_data: StageData,
		next_player_ship: ShipUnit,
		next_allies: Array[ShipUnit],
		next_enemies: Array[ShipUnit]
) -> void:
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
	for enemy: ShipUnit in next_enemies:
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
	if battle_services != null:
		battle_services.events.emit_battle_started(stage_id)
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

func _connect_ship_death(ship: ShipUnit, callback: Callable) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var health := ship.health
	if health == null:
		return
	if not health.is_connected("died", callback):
		health.connect("died", callback)
		_death_connections.append({
			"health": health,
			"callback": callback,
		})

func _on_player_died() -> void:
	_fail_battle()

func _on_enemy_died(enemy: ShipUnit) -> void:
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
		var enemy := enemies[index]
		if _is_ship_alive(enemy):
			return false
		enemies.remove_at(index)
	return true

func _is_ship_alive(ship_value: Variant) -> bool:
	if ship_value == null or not is_instance_valid(ship_value):
		return false
	var ship := ship_value as ShipUnit
	if ship == null:
		return false
	return ship.is_alive() and not ship.is_queued_for_deletion()

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
	var run_session := battle_services.run_session \
		if battle_services != null else null
	if run_session != null:
		run_session.capture_player_ship(player_ship)
		run_session.set_pending_rewards(reward_ids)
		var save_error := run_session.save_current_run()
		if save_error != OK:
			push_warning("Failed to save run after battle clear: %s" % save_error)
	if battle_services != null:
		battle_services.events.emit_battle_cleared(stage_id)
	battle_cleared.emit(stage_id)
	if battle_services != null:
		battle_services.game_flow.enter_reward()
	# TODO: Connect this to SceneLoader.load_reward() when reward scene exists.

func _fail_battle() -> void:
	if result_emitted:
		return
	result_emitted = true
	stop_battle()
	_resolve_player_components(false)
	_clear_active_projectiles()
	var run_session := battle_services.run_session \
		if battle_services != null else null
	if run_session != null:
		run_session.finish_run({
			"success": false,
			"stage_id": stage_id,
		})
		var clear_error := run_session.clear_saved_run()
		if clear_error != OK:
			push_warning("Failed to clear saved run after battle failure: %s" % clear_error)
	if battle_services != null:
		battle_services.events.emit_battle_failed(stage_id)
	battle_failed.emit(stage_id)
	if battle_services != null:
		battle_services.game_flow.enter_game_over()


func _resolve_player_components(success: bool) -> void:
	if player_ship == null or not is_instance_valid(player_ship):
		return
	player_ship.resolve_battle_end(success)


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
