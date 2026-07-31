extends RefCounted
class_name RunSessionReader

var _run_manager: Node


func setup(run_manager: Node) -> bool:
	_run_manager = run_manager
	return _run_manager == null or is_instance_valid(_run_manager)


func shutdown() -> void:
	_run_manager = null


func is_configured() -> bool:
	return _run_manager != null and is_instance_valid(_run_manager)


func is_run_active() -> bool:
	return _run_manager != null \
		and is_instance_valid(_run_manager) \
		and bool(_run_manager.get(&"is_run_active"))


func get_selected_player_ship_id() -> StringName:
	if _run_manager == null or not is_instance_valid(_run_manager):
		return &""
	return StringName(_run_manager.call(&"get_selected_player_ship_id"))


func get_player_ship_state() -> Dictionary:
	if _run_manager == null or not is_instance_valid(_run_manager):
		return {}
	var value: Variant = _run_manager.get(&"player_ship_state")
	return (value as Dictionary).duplicate(true) \
		if value is Dictionary else {}


func restore_carrier_air_group(ship: ShipUnit) -> void:
	if _run_manager != null and is_instance_valid(_run_manager):
		_run_manager.call(&"restore_carrier_air_group", ship)


func capture_player_ship(ship: ShipUnit) -> void:
	if _run_manager != null and is_instance_valid(_run_manager):
		_run_manager.call(&"capture_player_ship", ship)


func set_pending_rewards(reward_ids: Array[String]) -> void:
	if _run_manager != null and is_instance_valid(_run_manager):
		_run_manager.call(&"set_pending_rewards", reward_ids)


func save_current_run() -> Error:
	if _run_manager == null or not is_instance_valid(_run_manager):
		return ERR_UNCONFIGURED
	return _run_manager.call(&"save_current_run") as Error


func finish_run(result: Dictionary) -> void:
	if _run_manager != null and is_instance_valid(_run_manager):
		_run_manager.call(&"finish_run", result)


func clear_saved_run() -> Error:
	if _run_manager == null or not is_instance_valid(_run_manager):
		return ERR_UNCONFIGURED
	return _run_manager.call(&"clear_saved_run") as Error
