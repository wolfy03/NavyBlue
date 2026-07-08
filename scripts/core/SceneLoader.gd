extends Node

var current_scene_path := ""

func load_scene(scene_path: String) -> Error:
	if scene_path.is_empty():
		return ERR_INVALID_PARAMETER
	var error := get_tree().change_scene_to_file(scene_path)
	if error == OK:
		current_scene_path = scene_path
	return error

func load_packed_scene(scene: PackedScene) -> Error:
	if scene == null:
		return ERR_INVALID_PARAMETER
	var error := get_tree().change_scene_to_packed(scene)
	if error == OK:
		current_scene_path = scene.resource_path
	return error

func reload_current_scene() -> Error:
	return get_tree().reload_current_scene()
