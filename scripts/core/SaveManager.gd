extends Node

const PROFILE_SAVE_PATH := "user://profile.json"
const RUN_SAVE_PATH := "user://run.json"
const SETTINGS_SAVE_PATH := "user://settings.json"

func save_profile(data: Dictionary) -> Error:
	return save_data(_with_profile_defaults(data), PROFILE_SAVE_PATH)

func load_profile() -> Dictionary:
	return _with_profile_defaults(load_data(PROFILE_SAVE_PATH))

func profile_exists() -> bool:
	return save_exists(PROFILE_SAVE_PATH)

func delete_profile() -> Error:
	return delete_save(PROFILE_SAVE_PATH)

func save_run(data: Dictionary) -> Error:
	return save_data(_with_run_defaults(data), RUN_SAVE_PATH)

func load_run() -> Dictionary:
	return _with_run_defaults(load_data(RUN_SAVE_PATH))

func run_exists() -> bool:
	return save_exists(RUN_SAVE_PATH)

func delete_run() -> Error:
	return delete_save(RUN_SAVE_PATH)

func save_settings(data: Dictionary) -> Error:
	return save_data(_with_settings_defaults(data), SETTINGS_SAVE_PATH)

func load_settings() -> Dictionary:
	return _with_settings_defaults(load_data(SETTINGS_SAVE_PATH))

func settings_exists() -> bool:
	return save_exists(SETTINGS_SAVE_PATH)

func delete_settings() -> Error:
	return delete_save(SETTINGS_SAVE_PATH)

func save_data(data: Dictionary, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK

func load_data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func save_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func delete_save(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _default_profile_data() -> Dictionary:
	return {
		"version": 1,
		"player_level": 1,
		"experience": 0,
		"permanent_traits": [],
		"unlocked_traits": [],
		"achievements": [],
		"statistics": {
			"runs_started": 0,
			"runs_completed": 0,
			"ships_destroyed": 0,
		},
	}

func _default_run_data() -> Dictionary:
	return {
		"version": 1,
		"is_run_active": false,
		"current_sea_id": "",
		"current_stage_id": "",
		"current_stage_index": 0,
		"active_upgrades": [],
		"pending_rewards": [],
		"difficulty": 1.0,
		"currency": {
			"gold": 0,
			"scrap": 0,
		},
		"player_ship_state": {},
		"world_state": {},
		"started_at_msec": 0,
	}

func _default_settings_data() -> Dictionary:
	return {
		"version": 1,
		"video": {
			"fullscreen": false,
			"resolution": {
				"width": 1280,
				"height": 720,
			},
		},
		"audio": {
			"master_volume": 1.0,
			"music_volume": 0.8,
			"sfx_volume": 0.8,
		},
		"gameplay": {
			"edge_scroll_enabled": true,
			"edge_scroll_speed": 1.0,
			"camera_zoom_speed": 1.0,
		},
		"input": {},
	}

func _with_profile_defaults(data: Dictionary) -> Dictionary:
	return _merge_defaults(_default_profile_data(), data)

func _with_run_defaults(data: Dictionary) -> Dictionary:
	return _merge_defaults(_default_run_data(), data)

func _with_settings_defaults(data: Dictionary) -> Dictionary:
	return _merge_defaults(_default_settings_data(), data)

func _merge_defaults(defaults: Dictionary, data: Dictionary) -> Dictionary:
	var merged := defaults.duplicate(true)
	for key in data.keys():
		if merged.has(key) and merged[key] is Dictionary and data[key] is Dictionary:
			merged[key] = _merge_defaults(merged[key], data[key])
		else:
			merged[key] = data[key]
	return merged
