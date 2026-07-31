extends RefCounted
class_name GameFlowService

var _game_manager: Node


func setup(game_manager: Node) -> bool:
	_game_manager = game_manager
	return _game_manager == null or is_instance_valid(_game_manager)


func shutdown() -> void:
	_game_manager = null


func is_configured() -> bool:
	return _game_manager != null and is_instance_valid(_game_manager)


func enter_battle() -> void:
	_call(&"enter_battle")


func enter_reward() -> void:
	_call(&"enter_reward")


func enter_game_over() -> void:
	_call(&"enter_game_over")


func return_to_menu() -> void:
	_call(&"enter_main_menu")


func _call(method: StringName) -> void:
	if _game_manager != null and is_instance_valid(_game_manager) \
			and _game_manager.has_method(method):
		_game_manager.call(method)
