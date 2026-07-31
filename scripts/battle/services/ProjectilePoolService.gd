extends RefCounted
class_name ProjectilePoolService

var _object_pool: Node
var pool_acquire_count := 0
var pool_release_count := 0
var pool_acquire_failure_count := 0
var pool_release_failure_count := 0
var instantiate_fallback_count := 0
var foreign_instance_release_count := 0
var factory_instance_release_count := 0
var legacy_direct_pool_release_count := 0
var _active_pool_leases: Dictionary = {}
var _acquire_warning_emitted := false
var _release_warning_emitted := false

var acquire_count: int:
	get:
		return pool_acquire_count
var release_count: int:
	get:
		return pool_release_count


func setup(object_pool: Node) -> bool:
	shutdown()
	reset_metrics()
	if object_pool == null \
			or not is_instance_valid(object_pool) \
			or not object_pool.has_method(&"spawn") \
			or not object_pool.has_method(&"recycle"):
		return false
	_object_pool = object_pool
	return true


func shutdown() -> void:
	if _object_pool != null and is_instance_valid(_object_pool):
		for instance_id in _active_pool_leases.keys().duplicate():
			var reference := _active_pool_leases.get(instance_id) as WeakRef
			var instance := reference.get_ref() as Node \
				if reference != null else null
			if instance != null and is_instance_valid(instance):
				_release_pool_instance(instance)
			else:
				_active_pool_leases.erase(instance_id)
				pool_release_failure_count += 1
	_object_pool = null
	_acquire_warning_emitted = false
	_release_warning_emitted = false


func is_configured() -> bool:
	return _object_pool != null and is_instance_valid(_object_pool)


func reset_metrics() -> void:
	pool_acquire_count = 0
	pool_release_count = 0
	pool_acquire_failure_count = 0
	pool_release_failure_count = 0
	instantiate_fallback_count = 0
	foreign_instance_release_count = 0
	factory_instance_release_count = 0
	legacy_direct_pool_release_count = 0
	_active_pool_leases.clear()


func get_pool_outstanding_count() -> int:
	_prune_invalid_leases()
	return maxi(pool_acquire_count - pool_release_count, 0)


func get_active_pool_lease_count() -> int:
	_prune_invalid_leases()
	return _active_pool_leases.size()


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
	if is_configured():
		node = _object_pool.call(&"spawn", scene, parent) as Node
		if node != null:
			result.used_pool = true
			result.ownership = ProjectileCreationOwnership.Type.POOL
			node.set_meta(
				&"projectile_creation_ownership",
				ProjectileCreationOwnership.Type.POOL
			)
			_active_pool_leases[node.get_instance_id()] = weakref(node)
			pool_acquire_count += 1
		else:
			pool_acquire_failure_count += 1
	else:
		pool_acquire_failure_count += 1
	if node == null and allow_instantiate_fallback:
		node = scene.instantiate()
		if node != null:
			parent.add_child(node)
			result.ownership = ProjectileCreationOwnership.Type.FACTORY_INSTANCE
			node.set_meta(
				&"projectile_creation_ownership",
				ProjectileCreationOwnership.Type.FACTORY_INSTANCE
			)
			instantiate_fallback_count += 1
	if node != null:
		result.instance = node
	else:
		result.error = &"pool_acquire_failed"
		if not _acquire_warning_emitted:
			_acquire_warning_emitted = true
			push_warning("ProjectilePoolService could not acquire a projectile.")
	return result


func release(
		instance: Node,
		ownership: ProjectileCreationOwnership.Type = \
			ProjectileCreationOwnership.Type.NONE
) -> bool:
	if instance == null or not is_instance_valid(instance):
		return false
	var resolved_ownership := ownership
	if resolved_ownership == ProjectileCreationOwnership.Type.NONE:
		resolved_ownership = int(instance.get_meta(
			&"projectile_creation_ownership",
			ProjectileCreationOwnership.Type.NONE
		)) as ProjectileCreationOwnership.Type
	if resolved_ownership == ProjectileCreationOwnership.Type.NONE \
			and not str(instance.get_meta(&"pool_key", "")).is_empty():
		# Legacy direct ObjectPool.spawn callers predate lease tracking.
		resolved_ownership = ProjectileCreationOwnership.Type.POOL
	match resolved_ownership:
		ProjectileCreationOwnership.Type.POOL:
			return _release_pool_instance(instance)
		ProjectileCreationOwnership.Type.FACTORY_INSTANCE:
			_reset_instance(instance)
			instance.queue_free()
			factory_instance_release_count += 1
			return true
		_:
			foreign_instance_release_count += 1
			_reset_instance(instance)
			instance.queue_free()
			return true


func discard_acquired_instance(
		instance: Node,
		ownership: ProjectileCreationOwnership.Type
) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	if ownership == ProjectileCreationOwnership.Type.POOL:
		var instance_id := instance.get_instance_id()
		if _active_pool_leases.has(instance_id):
			_active_pool_leases.erase(instance_id)
			pool_release_count += 1
	_reset_instance(instance)
	instance.queue_free()


func _release_pool_instance(instance: Node) -> bool:
	var instance_id := instance.get_instance_id()
	if not _active_pool_leases.has(instance_id):
		var has_pool_identity := not str(
			instance.get_meta(&"pool_key", "")
		).is_empty() or not instance.scene_file_path.is_empty()
		if is_configured() \
				and has_pool_identity:
			legacy_direct_pool_release_count += 1
			return bool(_object_pool.call(&"recycle", instance))
		foreign_instance_release_count += 1
		return false
	var released := false
	if is_configured():
		released = bool(_object_pool.call(&"recycle", instance))
	if not released:
		pool_release_failure_count += 1
		_reset_instance(instance)
		instance.queue_free()
		if not _release_warning_emitted:
			_release_warning_emitted = true
			push_warning(
				"Projectile pool release failed; the instance was freed."
			)
	_active_pool_leases.erase(instance_id)
	pool_release_count += 1
	return true


func _reset_instance(instance: Node) -> void:
	var projectile := instance as ProjectileBase
	if projectile != null:
		projectile.reset_for_pool()
		return
	var rigid_projectile := instance as WeaponProjectileBase
	if rigid_projectile != null:
		rigid_projectile.reset_for_pool()
		return
	if instance.has_method(&"on_recycled_to_pool"):
		instance.call(&"on_recycled_to_pool")


func _prune_invalid_leases() -> void:
	for instance_id in _active_pool_leases.keys():
		var reference := _active_pool_leases.get(instance_id) as WeakRef
		if reference == null or reference.get_ref() == null:
			_active_pool_leases.erase(instance_id)
			pool_release_failure_count += 1
