extends RefCounted
class_name BattleServices

var event_bus: Node
var object_pool: Node
var run_manager: Node
var game_manager: Node
var faction_palette: FactionPalette


func setup(
		next_event_bus: Node,
		next_object_pool: Node,
		next_run_manager: Node,
		next_game_manager: Node,
		next_faction_palette: FactionPalette
) -> void:
	event_bus = next_event_bus
	object_pool = next_object_pool
	run_manager = next_run_manager
	game_manager = next_game_manager
	faction_palette = next_faction_palette


func publish(signal_name: StringName, arguments: Array = []) -> void:
	if event_bus == null or not is_instance_valid(event_bus) \
			or not event_bus.has_signal(signal_name):
		return
	# Autoload scripts intentionally remain untyped at this composition boundary.
	event_bus.callv(&"emit_signal", [signal_name] + arguments)


func spawn_pooled(scene: PackedScene, parent: Node) -> Node:
	if object_pool == null or not is_instance_valid(object_pool) \
			or not object_pool.has_method(&"spawn"):
		return null
	# ObjectPool is an Autoload adapter; domain objects do not inspect /root.
	return object_pool.call(&"spawn", scene, parent) as Node


func get_faction_color(team: StringName, fallback: Color) -> Color:
	if faction_palette == null \
			or faction_palette.get_faction(team) == null:
		return fallback
	return faction_palette.get_color(team)
