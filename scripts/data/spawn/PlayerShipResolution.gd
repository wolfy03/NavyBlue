extends RefCounted
class_name PlayerShipResolution

enum Source {
	TEST_OVERRIDE,
	RUN_SELECTION,
	GAME_DEFAULT,
}

var ship_id: StringName
var source: Source = Source.GAME_DEFAULT
var used_fallback := false


func get_source_name() -> String:
	return Source.keys()[int(source)].to_lower()
