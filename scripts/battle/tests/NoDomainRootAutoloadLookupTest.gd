extends SceneTree

const DOMAIN_DIRECTORIES := [
	"res://scripts/weapon",
	"res://scripts/combat",
	"res://scripts/effects",
	"res://scripts/unit",
	"res://scripts/ai",
]
const FORBIDDEN_TOKENS := [
	"/root/EventBus",
	"/root/ObjectPool",
]

var _failures := PackedStringArray()


func _initialize() -> void:
	for directory in DOMAIN_DIRECTORIES:
		_scan_directory(directory)
	for failure in _failures:
		push_error("DOMAIN AUTOLOAD LOOKUP: %s" % failure)
	print(
		"NO_DOMAIN_ROOT_AUTOLOAD_LOOKUP_TEST failures=%d"
		% _failures.size()
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
		elif entry.ends_with(".gd"):
			_scan_file(child_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _scan_file(path: String) -> void:
	var source := FileAccess.get_file_as_string(path)
	for token in FORBIDDEN_TOKENS:
		if source.contains(token):
			_failures.append("%s contains %s" % [path, token])
