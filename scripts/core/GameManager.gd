extends Node

enum GameMode {
	MAIN_MENU,
	RUN_PREPARE,
	BATTLE,
	REWARD,
	GAME_OVER,
}

const DEFAULT_BATTLE_SCENE := "res://scenes/world/battle_scene.tscn"

var current_mode: int = GameMode.MAIN_MENU
var previous_mode: int = GameMode.MAIN_MENU

func is_mode(mode: int) -> bool:
	return current_mode == mode

func change_mode(next_mode: int) -> void:
	if current_mode == next_mode:
		return
	previous_mode = current_mode
	current_mode = next_mode
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").game_mode_changed.emit(previous_mode, current_mode)

func enter_main_menu() -> void:
	change_mode(GameMode.MAIN_MENU)

func enter_run_prepare() -> void:
	change_mode(GameMode.RUN_PREPARE)

func enter_battle() -> void:
	change_mode(GameMode.BATTLE)

func enter_reward() -> void:
	change_mode(GameMode.REWARD)

func enter_game_over() -> void:
	change_mode(GameMode.GAME_OVER)

func start_battle_scene(scene_path: String = DEFAULT_BATTLE_SCENE) -> Error:
	enter_battle()
	if has_node("/root/SceneLoader"):
		return get_node("/root/SceneLoader").load_scene(scene_path)
	return ERR_UNAVAILABLE

func get_mode_name(mode: int = -1) -> String:
	if mode < 0:
		mode = current_mode
	match mode:
		GameMode.MAIN_MENU:
			return "MAIN_MENU"
		GameMode.RUN_PREPARE:
			return "RUN_PREPARE"
		GameMode.BATTLE:
			return "BATTLE"
		GameMode.REWARD:
			return "REWARD"
		GameMode.GAME_OVER:
			return "GAME_OVER"
	return "UNKNOWN"
