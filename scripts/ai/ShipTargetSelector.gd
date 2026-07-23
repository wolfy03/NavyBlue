extends RefCounted
class_name ShipTargetSelector


func find_target(owner_ship: Node3D, candidates: Array) -> Node3D:
	var valid_candidates := collect_valid_candidates(owner_ship, candidates)
	var nearest_hostile: Node3D
	var nearest_distance_squared := INF
	for candidate in valid_candidates:
		var distance_squared := owner_ship.global_position.distance_squared_to(candidate.global_position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_hostile = candidate
	return nearest_hostile


func collect_valid_candidates(owner_ship: Node3D, candidates: Array) -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for candidate_value in candidates:
		var candidate := candidate_value as ShipUnit
		if candidate == null or candidate == owner_ship or not is_instance_valid(candidate):
			continue
		if candidate.is_queued_for_deletion() or not candidate.is_inside_tree():
			continue
		if not _is_hostile(owner_ship, candidate) or not _is_alive(candidate):
			continue
		result.append(candidate)
	return result


func _is_hostile(owner_ship: Node3D, candidate: Node3D) -> bool:
	if owner_ship.has_method(&"is_hostile_to"):
		return bool(owner_ship.call(&"is_hostile_to", candidate))
	return FactionRelations.are_hostile(
		StringName(str(owner_ship.get(&"team"))),
		StringName(str(candidate.get(&"team")))
	)


func _is_alive(candidate: Node3D) -> bool:
	if candidate.has_method(&"is_alive"):
		return bool(candidate.call(&"is_alive"))
	var health := candidate.get_node_or_null("ShipHealth")
	return health == null or float(health.get(&"current_health")) > 0.0
