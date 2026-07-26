extends Node
class_name SplashEffectPool

@export var splash_effect_scene: PackedScene = preload("res://scenes/world/ocean/effects/water_splash_effect.tscn")
@export var foam_patch_scene: PackedScene = preload("res://scenes/world/ocean/effects/foam_patch.tscn")
@export_range(1, 128, 1, "or_greater") var splash_pool_size: int = 32
@export_range(1, 256, 1, "or_greater") var foam_pool_size: int = 64

var _splashes: Array = []
var _foams: Array = []
var _missing_splash_warned := false
var _invalid_splash_warned := false
var _missing_foam_warned := false
var _invalid_foam_warned := false


func _ready() -> void:
	_build_pool()


func spawn_splash(
		world_position: Vector3,
		strength: float,
		impact_velocity: Vector3 = Vector3.ZERO,
		surface_normal: Vector3 = Vector3.UP
) -> void:
	var effect := _acquire(_splashes)
	if effect == null:
		if not _missing_splash_warned:
			_missing_splash_warned = true
			push_warning(
				"SplashEffectPool could not acquire a splash effect."
			)
		return
	if not effect.has_method(&"activate"):
		if not _invalid_splash_warned:
			_invalid_splash_warned = true
			push_warning(
				"Water splash effect does not implement activate()."
			)
		return
	effect.call(
		&"activate",
		world_position,
		strength,
		impact_velocity,
		surface_normal
	)


func spawn_foam(world_position: Vector3, strength: float) -> void:
	var foam := _acquire(_foams)
	if foam == null:
		if not _missing_foam_warned:
			_missing_foam_warned = true
			push_warning("SplashEffectPool could not acquire a foam effect.")
		return
	if not foam.has_method(&"activate"):
		if not _invalid_foam_warned:
			_invalid_foam_warned = true
			push_warning("Foam effect does not implement activate().")
		return
	foam.call(&"activate", world_position, strength)


func get_active_splash_count() -> int:
	return _count_active(_splashes)


func get_active_foam_count() -> int:
	return _count_active(_foams)


func get_debug_state() -> Dictionary:
	return {
		"active_splashes": get_active_splash_count(),
		"active_foams": get_active_foam_count(),
		"splash_pool_size": _splashes.size(),
		"foam_pool_size": _foams.size(),
	}


func _build_pool() -> void:
	_create_instances(_splashes, splash_effect_scene, splash_pool_size)
	_create_instances(_foams, foam_patch_scene, foam_pool_size)


func _create_instances(target: Array, scene: PackedScene, count: int) -> void:
	if scene == null:
		return
	for _index in count:
		var node := scene.instantiate()
		add_child(node)
		target.append(node)
		if node.has_method(&"deactivate"):
			node.call(&"deactivate")
		else:
			node.visible = false
			node.set_process(false)
			node.set_physics_process(false)


func _acquire(pool: Array) -> Node:
	_prune_freed_nodes(pool)
	for node_value: Variant in pool:
		var node := node_value as Node
		if _is_available(node):
			return node

	var oldest: Node
	var oldest_time := INF
	for node_value: Variant in pool:
		var node := node_value as Node
		if node == null:
			continue
		var activated_time := float(node.get(&"last_activated_msec")) if node.get(&"last_activated_msec") != null else 0.0
		if activated_time < oldest_time:
			oldest_time = activated_time
			oldest = node
	if oldest != null and oldest.has_method(&"deactivate"):
		oldest.call(&"deactivate")
	return oldest


func _is_available(node_value: Variant) -> bool:
	if node_value == null or not is_instance_valid(node_value):
		return false
	var node := node_value as Node
	if node == null:
		return false
	if node.has_method(&"is_available"):
		return bool(node.call(&"is_available"))
	var active_value: Variant = node.get(&"active")
	return active_value == null or not bool(active_value)


func _count_active(pool: Array) -> int:
	_prune_freed_nodes(pool)
	var count := 0
	for node_value: Variant in pool:
		if not _is_available(node_value):
			count += 1
	return count


func _prune_freed_nodes(pool: Array) -> void:
	for index in range(pool.size() - 1, -1, -1):
		var node_value: Variant = pool[index]
		if node_value == null or not is_instance_valid(node_value) \
				or not (node_value is Node):
			pool.remove_at(index)
