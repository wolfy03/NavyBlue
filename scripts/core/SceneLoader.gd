extends Node

func load_scene(scene_path: String) -> Error:
	return get_tree().change_scene_to_file(scene_path)

func reload_current_scene() -> Error:
	return get_tree().reload_current_scene()
