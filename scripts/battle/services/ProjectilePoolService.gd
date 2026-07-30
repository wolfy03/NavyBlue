extends RefCounted
class_name ProjectilePoolService

var _object_pool: Node
var acquire_count := 0
var release_count := 0


func setup(object_pool: Node) -> void:
	shutdown()
	_object_pool = object_pool


func shutdown() -> void:
	_object_pool = null
	acquire_count = 0
	release_count = 0


func acquire(scene: PackedScene, parent: Node) -> Node:
	if scene == null or parent == null or not is_instance_valid(parent):
		return null
	var node: Node
	if _object_pool != null and is_instance_valid(_object_pool) \
			and _object_pool.has_method(&"spawn"):
		node = _object_pool.call(&"spawn", scene, parent) as Node
	else:
		node = scene.instantiate()
		if node != null:
			parent.add_child(node)
	if node != null:
		acquire_count += 1
	return node


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
	if released:
		release_count += 1
	return released
