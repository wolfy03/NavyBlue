extends Node

var _pool: Dictionary = {}

func spawn(scene: PackedScene, parent: Node) -> Node:
	if scene == null or parent == null:
		return null
	var key := scene.resource_path
	var objects: Array = _pool.get(key, [])
	var node: Node = objects.pop_back() if not objects.is_empty() else scene.instantiate()
	_pool[key] = objects
	node.set_meta("pool_key", key)
	parent.add_child(node)
	node.set_process(true)
	node.set_physics_process(true)
	var spawned_body := node as RigidBody3D
	if spawned_body != null:
		spawned_body.linear_velocity = Vector3.ZERO
		spawned_body.angular_velocity = Vector3.ZERO
		spawned_body.sleeping = false
	node.show()
	if node.has_method(&"on_spawned_from_pool"):
		node.call(&"on_spawned_from_pool")
	return node

func recycle(node: Node) -> void:
	if node == null:
		return
	var key := str(node.get_meta("pool_key", ""))
	if key.is_empty():
		key = node.scene_file_path
	if key.is_empty():
		node.queue_free()
		return
	if node.has_method(&"on_recycled_to_pool"):
		node.call(&"on_recycled_to_pool")
	node.hide()
	node.set_process(false)
	node.set_physics_process(false)
	var recycled_body := node as RigidBody3D
	if recycled_body != null:
		recycled_body.linear_velocity = Vector3.ZERO
		recycled_body.angular_velocity = Vector3.ZERO
		recycled_body.sleeping = true
	if node.get_parent():
		node.get_parent().remove_child(node)
	var objects: Array = _pool.get(key, [])
	objects.append(node)
	_pool[key] = objects

func clear_pool() -> void:
	for objects in _pool.values():
		if not objects is Array:
			continue
		for node in objects:
			if is_instance_valid(node):
				node.queue_free()
	_pool.clear()
