extends Node

var _pool: Dictionary = {}

func spawn(scene: PackedScene, parent: Node) -> Node:
	var key := scene.resource_path
	var objects: Array = _pool.get(key, [])
	var node: Node = objects.pop_back() if not objects.is_empty() else scene.instantiate()
	_pool[key] = objects
	parent.add_child(node)
	node.set_process(true)
	node.set_physics_process(true)
	node.show()
	return node

func recycle(node: Node) -> void:
	if node.scene_file_path.is_empty():
		node.queue_free()
		return
	node.hide()
	node.set_process(false)
	node.set_physics_process(false)
	if node.get_parent():
		node.get_parent().remove_child(node)
	var objects: Array = _pool.get(node.scene_file_path, [])
	objects.append(node)
	_pool[node.scene_file_path] = objects
