extends Node3D
class_name CombatEffectPool

@export var ship_hit_effect_scene: PackedScene = preload("res://scenes/world/effects/ship_hit_explosion_effect.tscn")
@export_range(1, 128, 1, "or_greater") var ship_hit_pool_size: int = 32

var _ship_hit_effects: Array[Node] = []


func _ready() -> void:
	_build_pool()
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null and not event_bus.projectile_ship_impact.is_connected(_on_projectile_ship_impact):
		event_bus.projectile_ship_impact.connect(_on_projectile_ship_impact)


func _exit_tree() -> void:
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null and event_bus.projectile_ship_impact.is_connected(_on_projectile_ship_impact):
		event_bus.projectile_ship_impact.disconnect(_on_projectile_ship_impact)


func spawn_ship_hit(position: Vector3, strength: float, penetrated: bool) -> void:
	var effect := _acquire()
	if effect != null and effect.has_method(&"activate"):
		effect.call(&"activate", position, strength, penetrated)


func get_active_ship_hit_count() -> int:
	var count := 0
	for effect in _ship_hit_effects:
		if not _is_available(effect):
			count += 1
	return count


func _build_pool() -> void:
	if ship_hit_effect_scene == null:
		return
	for _index in ship_hit_pool_size:
		var effect := ship_hit_effect_scene.instantiate()
		add_child(effect)
		_ship_hit_effects.append(effect)
		if effect.has_method(&"deactivate"):
			effect.call(&"deactivate")


func _acquire() -> Node:
	for effect in _ship_hit_effects:
		if _is_available(effect):
			return effect
	var oldest: Node
	var oldest_time := INF
	for effect in _ship_hit_effects:
		var activated_time := float(effect.get(&"last_activated_msec")) if effect.get(&"last_activated_msec") != null else 0.0
		if activated_time < oldest_time:
			oldest_time = activated_time
			oldest = effect
	if oldest != null and oldest.has_method(&"deactivate"):
		oldest.call(&"deactivate")
	return oldest


func _is_available(effect: Node) -> bool:
	if effect == null:
		return false
	if effect.has_method(&"is_available"):
		return bool(effect.call(&"is_available"))
	return not bool(effect.get(&"active"))


func _on_projectile_ship_impact(position: Vector3, strength: float, penetrated: bool) -> void:
	spawn_ship_hit(position, strength, penetrated)
