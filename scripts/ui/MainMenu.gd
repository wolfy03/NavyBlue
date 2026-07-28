extends Control

const BATTLE_SCENE_PATH := "res://scenes/world/battle_scene.tscn"
const DEFAULT_PLAYER_SHIP_ID := GameConfig.DEFAULT_PLAYER_SHIP_ID
const SHIP_DATABASE_SCRIPT := preload(
	"res://scripts/data/ShipDatabase.gd"
)
const STARTING_SHIP_ORDER := [
	"dd_bluewind",
	"cl_tidebreaker",
	"bb_ironwake",
	"cv_seabastion",
]

@onready var tabs: TabContainer = $Root/Panel/VBox/Tabs
@onready var new_game_button: Button = $Root/Panel/VBox/Tabs/NewGame/NewGameContent/StartNewGameButton
@onready var new_game_status: Label = $Root/Panel/VBox/Tabs/NewGame/NewGameContent/NewGameStatus
@onready var starting_ship_selector: OptionButton = \
	$Root/Panel/VBox/Tabs/NewGame/NewGameContent/StartingShip/StartingShipSelector
@onready var continue_button: Button = $Root/Panel/VBox/Tabs/Continue/ContinueContent/ContinueButton
@onready var continue_status: Label = $Root/Panel/VBox/Tabs/Continue/ContinueContent/ContinueStatus
@onready var fullscreen_check: CheckBox = $Root/Panel/VBox/Tabs/Settings/SettingsContent/FullscreenCheck
@onready var master_volume_slider: HSlider = $Root/Panel/VBox/Tabs/Settings/SettingsContent/MasterVolumeSlider
@onready var edge_scroll_slider: HSlider = $Root/Panel/VBox/Tabs/Settings/SettingsContent/EdgeScrollSlider
@onready var settings_status: Label = $Root/Panel/VBox/Tabs/Settings/SettingsContent/SettingsStatus
@onready var save_settings_button: Button = $Root/Panel/VBox/Tabs/Settings/SettingsContent/SaveSettingsButton
@onready var quit_button: Button = $Root/Panel/VBox/Tabs/Quit/QuitContent/QuitButton

var _ship_database := SHIP_DATABASE_SCRIPT.new()

func _ready() -> void:
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_main_menu()
	_connect_buttons()
	_populate_starting_ship_selector()
	_load_settings_to_controls()
	_refresh_continue_state()

func _connect_buttons() -> void:
	new_game_button.pressed.connect(_on_start_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	save_settings_button.pressed.connect(_on_save_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_start_new_game_pressed() -> void:
	if not _has_required_managers():
		new_game_status.text = "Managers are not ready."
		return

	var save_manager = get_node("/root/SaveManager")
	var run_manager = get_node("/root/RunManager")
	var game_manager = get_node("/root/GameManager")
	var selected_ship_id := _get_selected_ship_id()

	_increment_runs_started(save_manager)
	save_manager.delete_run()
	run_manager.start_new_run({
		"sea_id": "test_sea",
		"stage_id": "test_level",
		"stage_index": 0,
		"difficulty": 1.0,
		"currency": {
			"gold": 0,
			"scrap": 0,
		},
		"player_ship_state": {
			"ship_id": selected_ship_id,
		},
	})

	var save_error: Error = run_manager.save_current_run()
	if save_error != OK:
		new_game_status.text = "Failed to save new run: %d" % save_error
		_refresh_continue_state()
		return

	game_manager.enter_run_prepare()
	var scene_error: Error = game_manager.start_battle_scene(BATTLE_SCENE_PATH)
	if scene_error != OK:
		new_game_status.text = "Failed to load battle scene: %d" % scene_error

func _on_continue_pressed() -> void:
	if not _has_required_managers():
		continue_status.text = "Managers are not ready."
		return

	var run_manager = get_node("/root/RunManager")
	var game_manager = get_node("/root/GameManager")

	if not run_manager.load_saved_run():
		continue_status.text = "No saved run found."
		_refresh_continue_state()
		return

	var scene_error: Error = game_manager.start_battle_scene(BATTLE_SCENE_PATH)
	if scene_error != OK:
		continue_status.text = "Failed to load battle scene: %d" % scene_error

func _on_save_settings_pressed() -> void:
	if not has_node("/root/SaveManager"):
		settings_status.text = "SaveManager is not ready."
		return

	var settings := {
		"video": {
			"fullscreen": fullscreen_check.button_pressed,
		},
		"audio": {
			"master_volume": master_volume_slider.value,
		},
		"gameplay": {
			"edge_scroll_speed": edge_scroll_slider.value,
		},
	}

	var error: Error = get_node("/root/SaveManager").save_settings(settings)
	settings_status.text = "Settings saved." if error == OK else "Failed to save settings: %d" % error

func _on_quit_pressed() -> void:
	get_tree().quit()

func _has_required_managers() -> bool:
	return has_node("/root/GameManager") and has_node("/root/RunManager") and has_node("/root/SaveManager")

func _refresh_continue_state() -> void:
	if not has_node("/root/SaveManager"):
		continue_button.disabled = true
		continue_status.text = "SaveManager is not ready."
		return

	var save_manager = get_node("/root/SaveManager")
	var has_run_save: bool = save_manager.run_exists()
	continue_button.disabled = not has_run_save
	if has_run_save:
		var run_data: Dictionary = save_manager.load_run()
		continue_status.text = "Saved run: %s / %s" % [
			run_data.get("current_sea_id", "unknown"),
			run_data.get("current_stage_id", "unknown"),
		]
	else:
		continue_status.text = "No saved run."

func _load_settings_to_controls() -> void:
	if not has_node("/root/SaveManager"):
		settings_status.text = "SaveManager is not ready."
		return

	var settings: Dictionary = get_node("/root/SaveManager").load_settings()
	var video: Dictionary = settings.get("video", {})
	var audio: Dictionary = settings.get("audio", {})
	var gameplay: Dictionary = settings.get("gameplay", {})

	fullscreen_check.button_pressed = bool(video.get("fullscreen", false))
	master_volume_slider.value = float(audio.get("master_volume", 1.0))
	edge_scroll_slider.value = float(gameplay.get("edge_scroll_speed", 1.0))
	settings_status.text = "Settings loaded."

func _increment_runs_started(save_manager) -> void:
	var profile: Dictionary = save_manager.load_profile()
	var statistics: Dictionary = profile.get("statistics", {})
	statistics["runs_started"] = int(statistics.get("runs_started", 0)) + 1
	profile["statistics"] = statistics
	save_manager.save_profile(profile)


func _populate_starting_ship_selector() -> void:
	starting_ship_selector.clear()
	var default_index := 0
	for ship_id in STARTING_SHIP_ORDER:
		var data := _ship_database.get_ship(ship_id)
		if data == null:
			continue
		var label := "%s (%s)" % [
			data.display_name,
			_ship_database.class_label(data.ship_class),
		]
		starting_ship_selector.add_item(label)
		var item_index := starting_ship_selector.item_count - 1
		starting_ship_selector.set_item_metadata(item_index, ship_id)
		if ship_id == DEFAULT_PLAYER_SHIP_ID:
			default_index = item_index
	if starting_ship_selector.item_count > 0:
		starting_ship_selector.select(default_index)


func _get_selected_ship_id() -> String:
	var selected_index := starting_ship_selector.selected
	if selected_index < 0 \
			or selected_index >= starting_ship_selector.item_count:
		return DEFAULT_PLAYER_SHIP_ID
	var ship_id := str(
		starting_ship_selector.get_item_metadata(selected_index)
	)
	return ship_id if not ship_id.is_empty() else DEFAULT_PLAYER_SHIP_ID
