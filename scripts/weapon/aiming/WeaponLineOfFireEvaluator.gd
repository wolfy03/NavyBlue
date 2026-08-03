extends RefCounted
class_name WeaponLineOfFireEvaluator


func evaluate(
		mount: WeaponMount,
		target: ShipUnit,
		world_point: Vector3
) -> WeaponLineOfFireResult:
	var result := WeaponLineOfFireResult.new()
	if mount == null or not is_instance_valid(mount):
		result.blocked_reason = &"invalid_mount"
		return result
	if target == null or not is_instance_valid(target):
		result.blocked_reason = &"invalid_target"
		return result
	if not mount.is_inside_tree() or mount.get_world_3d() == null:
		result.blocked_reason = &"missing_world"
		return result
	var start := mount.get_muzzle_position()
	var end := world_point
	var delta := end - start
	if not start.is_finite() or not end.is_finite() \
			or delta.length_squared() <= 0.01:
		result.blocked_reason = &"invalid_ray"
		return result
	# Start just beyond the muzzle. The owning hull is intentionally not
	# excluded: a deck or superstructure between muzzle and target blocks fire.
	start += delta.normalized() * 0.5
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := mount.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		result.safe = true
		return result
	var collider_value: Variant = hit.get("collider")
	if collider_value == null or not is_instance_valid(collider_value):
		result.blocked_reason = &"unknown_obstruction"
		return result
	var collider := collider_value as Node
	if collider == target or target.is_ancestor_of(collider):
		result.safe = true
		return result
	result.blocker_instance_id = collider.get_instance_id()
	var blocker_ship := _find_ship_ancestor(collider)
	if blocker_ship != null:
		if blocker_ship == mount.get_owner_ship():
			result.blocked_reason = &"own_ship_blocked"
		elif not FactionRelations.are_hostile(mount.owner_team, blocker_ship.team):
			result.blocked_reason = &"friendly_blocked"
		else:
			# Hitting a different hostile on the same firing line is not friendly
			# fire and remains a valid combat outcome.
			result.safe = true
		return result
	result.blocked_reason = &"world_obstruction"
	return result


func _find_ship_ancestor(node: Node) -> ShipUnit:
	var current := node
	while current != null:
		var ship := current as ShipUnit
		if ship != null:
			return ship
		current = current.get_parent()
	return null
