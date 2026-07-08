extends Node

const DEFAULT_SAVE_PATH := "user://save_game.json"

func save_data(data: Dictionary, path: String = DEFAULT_SAVE_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK

func load_data(path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func save_exists(path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

func delete_save(path: String = DEFAULT_SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
