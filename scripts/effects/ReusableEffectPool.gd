extends Node
class_name ReusableEffectPool

@export var effect_scene: PackedScene
@export_range(1, 128, 1, "or_greater") var pool_size := 24

var _effects: Array = []
var _missing_effect_warned := false
var _invalid_effect_warned := false


func setup(next_scene: PackedScene, next_pool_size: int) -> void:
	effect_scene = next_scene
	pool_size = maxi(next_pool_size, 1)
	if is_inside_tree():
		_build_pool()


func _ready() -> void:
	_build_pool()


func spawn_effect(arguments: Array) -> Node:
	var effect := _acquire()
	if effect == null:
		if not _missing_effect_warned:
			_missing_effect_warned = true
			push_warning("ReusableEffectPool could not acquire an effect.")
		return null
	if not effect.has_method(&"activate"):
		if not _invalid_effect_warned:
			_invalid_effect_warned = true
			push_warning("Reusable effect does not implement activate().")
		return null
	effect.callv(&"activate", arguments)
	return effect


func get_active_count() -> int:
	_prune_freed_effects()
	var count := 0
	for effect_value: Variant in _effects:
		if not _is_available(effect_value):
			count += 1
	return count


func get_pool_size() -> int:
	_prune_freed_effects()
	return _effects.size()


func clear_pool() -> void:
	for effect_value: Variant in _effects:
		if effect_value != null and is_instance_valid(effect_value):
			(effect_value as Node).queue_free()
	_effects.clear()


func _build_pool() -> void:
	_prune_freed_effects()
	if effect_scene == null:
		return
	while _effects.size() < pool_size:
		if _create_effect() == null:
			return


func _create_effect() -> Node:
	if effect_scene == null:
		return null
	var effect := effect_scene.instantiate()
	if effect == null:
		return null
	add_child(effect)
	_effects.append(effect)
	if effect.has_method(&"deactivate"):
		effect.call(&"deactivate")
	else:
		effect.hide()
		effect.set_process(false)
		effect.set_physics_process(false)
	return effect


func _acquire() -> Node:
	_prune_freed_effects()
	for effect_value: Variant in _effects:
		if _is_available(effect_value):
			return effect_value as Node
	if _effects.size() < pool_size:
		return _create_effect()

	var oldest: Node
	var oldest_time := INF
	for effect_value: Variant in _effects:
		if effect_value == null or not is_instance_valid(effect_value):
			continue
		var effect := effect_value as Node
		if effect == null:
			continue
		var activated_value: Variant = effect.get(&"last_activated_msec")
		var activated_time := float(activated_value) \
			if activated_value != null else 0.0
		if activated_time < oldest_time:
			oldest_time = activated_time
			oldest = effect
	if oldest != null and oldest.has_method(&"deactivate"):
		oldest.call(&"deactivate")
	return oldest


func _is_available(effect_value: Variant) -> bool:
	if effect_value == null or not is_instance_valid(effect_value):
		return false
	var effect := effect_value as Node
	if effect == null:
		return false
	if effect.has_method(&"is_available"):
		return bool(effect.call(&"is_available"))
	var active_value: Variant = effect.get(&"active")
	return active_value == null or not bool(active_value)


func _prune_freed_effects() -> void:
	for index in range(_effects.size() - 1, -1, -1):
		var effect_value: Variant = _effects[index]
		if effect_value == null or not is_instance_valid(effect_value) \
				or not (effect_value is Node):
			_effects.remove_at(index)
