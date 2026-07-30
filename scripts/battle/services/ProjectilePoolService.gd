extends RefCounted
class_name ProjectilePoolService

var _object_pool: Node
var acquire_count := 0
var release_count := 0
var _acquire_warning_emitted := false
var _release_warning_emitted := false


func setup(object_pool: Node) -> void:
	shutdown()
	_object_pool = object_pool


func shutdown() -> void:
	_object_pool = null
	acquire_count = 0
	release_count = 0
	_acquire_warning_emitted = false
	_release_warning_emitted = false


func acquire_result(
		scene: PackedScene,
		parent: Node,
		allow_instantiate_fallback := true
) -> PoolAcquireResult:
	var result := PoolAcquireResult.new()
	if scene == null or parent == null or not is_instance_valid(parent):
		result.error = &"invalid_argument"
		return result
	var node: Node
	if _object_pool != null and is_instance_valid(_object_pool) \
			and _object_pool.has_method(&"spawn"):
		node = _object_pool.call(&"spawn", scene, parent) as Node
		result.used_pool = node != null
	if node == null and allow_instantiate_fallback:
		node = scene.instantiate()
		if node != null:
			parent.add_child(node)
	if node != null:
		acquire_count += 1
		result.instance = node
	else:
		result.error = &"pool_acquire_failed"
		if not _acquire_warning_emitted:
			_acquire_warning_emitted = true
			push_warning("ProjectilePoolService could not acquire a projectile.")
	return result


func release(instance: Node) -> bool:
	if instance == null or not is_instance_valid(instance):
		return false
	var projectile := instance as ProjectileBase
	if projectile != null and not bool(
		instance.get_meta(&"in_object_pool", false)
	):
		projectile.reset_for_pool()
	var rigid_projectile := instance as WeaponProjectileBase
	if rigid_projectile != null and not bool(
		instance.get_meta(&"in_object_pool", false)
	):
		rigid_projectile.reset_for_pool()
	var released := false
	if _object_pool != null and is_instance_valid(_object_pool) \
			and _object_pool.has_method(&"recycle"):
		released = bool(_object_pool.call(&"recycle", instance))
	else:
		instance.queue_free()
		released = true
	if not released:
		if projectile != null:
			projectile.reset_for_pool()
		elif rigid_projectile != null:
			rigid_projectile.reset_for_pool()
		instance.queue_free()
		released = true
		if not _release_warning_emitted:
			_release_warning_emitted = true
			push_warning(
				"Projectile pool release failed; the instance was freed."
			)
	if released:
		release_count += 1
	return released
