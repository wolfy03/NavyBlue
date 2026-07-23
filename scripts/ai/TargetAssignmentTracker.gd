extends RefCounted
class_name TargetAssignmentTracker

static var _owner_assignments: Dictionary = {}
static var _target_counts: Dictionary = {}


static func assign(owner_ship: Node, target_ship: Node) -> void:
	if owner_ship == null or not is_instance_valid(owner_ship):
		return
	unassign(owner_ship)
	if target_ship == null or not is_instance_valid(target_ship):
		return
	var owner_id := owner_ship.get_instance_id()
	var target_id := target_ship.get_instance_id()
	_owner_assignments[owner_id] = {
		"owner_ref": weakref(owner_ship),
		"target_ref": weakref(target_ship),
		"target_id": target_id,
	}
	_target_counts[target_id] = int(_target_counts.get(target_id, 0)) + 1


static func unassign(owner_ship: Node) -> void:
	if owner_ship == null:
		return
	var owner_id := owner_ship.get_instance_id()
	if not _owner_assignments.has(owner_id):
		return
	var assignment: Dictionary = _owner_assignments[owner_id]
	_decrement_target(int(assignment.get("target_id", 0)))
	_owner_assignments.erase(owner_id)


static func get_attacker_count(target_ship: Node) -> int:
	if target_ship == null or not is_instance_valid(target_ship):
		return 0
	return int(_target_counts.get(target_ship.get_instance_id(), 0))


static func cleanup() -> void:
	for owner_id in _owner_assignments.keys():
		var assignment: Dictionary = _owner_assignments[owner_id]
		var owner_ref := assignment.get("owner_ref") as WeakRef
		var target_ref := assignment.get("target_ref") as WeakRef
		if owner_ref == null or owner_ref.get_ref() == null \
			or target_ref == null or target_ref.get_ref() == null:
			_decrement_target(int(assignment.get("target_id", 0)))
			_owner_assignments.erase(owner_id)


static func clear_all() -> void:
	_owner_assignments.clear()
	_target_counts.clear()


static func _decrement_target(target_id: int) -> void:
	if target_id == 0 or not _target_counts.has(target_id):
		return
	var next_count := int(_target_counts[target_id]) - 1
	if next_count <= 0:
		_target_counts.erase(target_id)
	else:
		_target_counts[target_id] = next_count
