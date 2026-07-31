extends Node
class_name ReusableEffectPool

@export var effect_scene: PackedScene
@export_range(1, 128, 1, "or_greater") var pool_size := 24

var _effects: Array[PooledEffectBase] = []
var _missing_effect_warned := false
var _invalid_effect_warned := false


func setup(next_scene: PackedScene, next_pool_size: int) -> void:
	effect_scene = next_scene
	pool_size = maxi(next_pool_size, 1)
	if is_inside_tree():
		_build_pool()


func _ready() -> void:
	_build_pool()


func spawn_effect(request: EffectRequest) -> PooledEffectBase:
	var effect := _acquire()
	if effect == null:
		if not _missing_effect_warned:
			_missing_effect_warned = true
			push_warning("ReusableEffectPool could not acquire an effect.")
		return null
	effect.activate(request)
	return effect


func get_active_count() -> int:
	_prune_freed_effects()
	var count := 0
	for effect in _effects:
		if not effect.is_available():
			count += 1
	return count


func get_pool_size() -> int:
	_prune_freed_effects()
	return _effects.size()


func clear_pool() -> void:
	for effect in _effects:
		if effect != null and is_instance_valid(effect):
			effect.deactivate()
			effect.queue_free()
	_effects.clear()


func _build_pool() -> void:
	_prune_freed_effects()
	if effect_scene == null:
		return
	while _effects.size() < pool_size:
		if _create_effect() == null:
			return


func _create_effect() -> PooledEffectBase:
	if effect_scene == null:
		return null
	var node := effect_scene.instantiate()
	var effect := node as PooledEffectBase
	if effect == null:
		if node != null:
			node.queue_free()
		if not _invalid_effect_warned:
			_invalid_effect_warned = true
			push_error("Effect scene root must inherit PooledEffectBase.")
		return null
	add_child(effect)
	_effects.append(effect)
	effect.deactivate()
	return effect


func _acquire() -> PooledEffectBase:
	_prune_freed_effects()
	for effect in _effects:
		if effect.is_available():
			return effect
	if _effects.size() < pool_size:
		return _create_effect()

	var oldest: PooledEffectBase
	var oldest_time := INF
	for effect in _effects:
		if effect == null or not is_instance_valid(effect):
			continue
		var activated_time := float(effect.last_activated_msec)
		if activated_time < oldest_time:
			oldest_time = activated_time
			oldest = effect
	if oldest != null:
		oldest.deactivate()
	return oldest


func _prune_freed_effects() -> void:
	for index in range(_effects.size() - 1, -1, -1):
		var effect := _effects[index]
		if effect == null or not is_instance_valid(effect):
			_effects.remove_at(index)
