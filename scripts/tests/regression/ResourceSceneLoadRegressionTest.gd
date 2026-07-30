extends SceneTree

var _failures: PackedStringArray = []
var _path_filter := ""


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_path_filter = OS.get_environment("NAVY_RESOURCE_AUDIT_FILTER")
	_scan_directory("res://resources")
	_scan_directory("res://scenes")
	await process_frame
	await process_frame
	for failure in _failures:
		push_error("RESOURCE LOAD REGRESSION: %s" % failure)
	print(
		"RESOURCE_SCENE_LOAD_REGRESSION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _scan_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		_failures.append("Cannot open %s" % path)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = directory.get_next()
			continue
		var child_path := path.path_join(entry)
		if directory.current_is_dir():
			_scan_directory(child_path)
		elif entry.ends_with(".tres") or entry.ends_with(".tscn"):
			_verify_resource(child_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _verify_resource(path: String) -> void:
	if not _path_filter.is_empty() and path != _path_filter:
		return
	var resource := load(path)
	if resource == null:
		_failures.append("Failed to load %s" % path)
		return
	var scene := resource as PackedScene
	if scene == null:
		return
	# BattleStartupRegressionTest enters and frees the complete battle scene.
	# Instantiating it outside SceneTree leaks a renderer RID in headless Godot.
	if path == "res://scenes/world/battle_scene.tscn":
		return
	var instance := scene.instantiate()
	if instance == null:
		_failures.append("Failed to instantiate %s" % path)
		return
	for environment_node in instance.find_children(
		"*",
		"WorldEnvironment",
		true,
		false
	):
		(environment_node as WorldEnvironment).environment = null
	instance.free()
