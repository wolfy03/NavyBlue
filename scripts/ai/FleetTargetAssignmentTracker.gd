extends RefCounted
class_name FleetTargetAssignmentTracker

var cleanup_count := 0
var _owner_assignments: Dictionary = {}
var _target_counts: Dictionary = {}


func assign(attacker: ShipUnit, target: ShipUnit) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	unassign(attacker)
	if target == null or not is_instance_valid(target):
		return
	var attacker_id := attacker.get_instance_id()
	var target_id := target.get_instance_id()
	_owner_assignments[attacker_id] = {
		"attacker_ref": weakref(attacker),
		"target_ref": weakref(target),
		"target_id": target_id,
	}
	_target_counts[target_id] = int(_target_counts.get(target_id, 0)) + 1


func unassign(attacker: ShipUnit) -> void:
	if attacker == null:
		return
	var attacker_id := attacker.get_instance_id()
	if not _owner_assignments.has(attacker_id):
		return
	var assignment: Dictionary = _owner_assignments[attacker_id]
	_decrement_target(int(assignment.get("target_id", 0)))
	_owner_assignments.erase(attacker_id)


func get_target(attacker: ShipUnit) -> ShipUnit:
	if attacker == null or not _owner_assignments.has(attacker.get_instance_id()):
		return null
	var assignment: Dictionary = _owner_assignments[attacker.get_instance_id()]
	var target_ref := assignment.get("target_ref") as WeakRef
	return target_ref.get_ref() as ShipUnit if target_ref != null else null


func get_attacker_count(target: ShipUnit) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	return int(_target_counts.get(target.get_instance_id(), 0))


func get_attackers(target: ShipUnit) -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	if target == null:
		return result
	var target_id := target.get_instance_id()
	for assignment_value in _owner_assignments.values():
		var assignment := assignment_value as Dictionary
		if int(assignment.get("target_id", 0)) != target_id:
			continue
		var attacker_ref := assignment.get("attacker_ref") as WeakRef
		var attacker := attacker_ref.get_ref() as ShipUnit if attacker_ref != null else null
		if attacker != null and is_instance_valid(attacker):
			result.append(attacker)
	return result


func cleanup() -> void:
	cleanup_count += 1
	for attacker_id in _owner_assignments.keys():
		var assignment: Dictionary = _owner_assignments[attacker_id]
		var attacker_ref := assignment.get("attacker_ref") as WeakRef
		var target_ref := assignment.get("target_ref") as WeakRef
		var attacker := attacker_ref.get_ref() as ShipUnit if attacker_ref != null else null
		var target := target_ref.get_ref() as ShipUnit if target_ref != null else null
		if not _is_live_ship(attacker) or not _is_live_ship(target):
			_decrement_target(int(assignment.get("target_id", 0)))
			_owner_assignments.erase(attacker_id)


func clear_all() -> void:
	_owner_assignments.clear()
	_target_counts.clear()


func get_assignment_count() -> int:
	return _owner_assignments.size()


func get_debug_target_counts() -> Dictionary:
	return _target_counts.duplicate()


func _decrement_target(target_id: int) -> void:
	if target_id == 0 or not _target_counts.has(target_id):
		return
	var next_count := int(_target_counts[target_id]) - 1
	if next_count <= 0:
		_target_counts.erase(target_id)
	else:
		_target_counts[target_id] = next_count


func _is_live_ship(ship: ShipUnit) -> bool:
	return ship != null and is_instance_valid(ship) and not ship.is_queued_for_deletion() \
		and ship.is_inside_tree() and ship.is_alive()
