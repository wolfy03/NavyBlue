extends RefCounted
class_name TestTeardownAudit


static func inspect_subtree(
		subtree_root: Node,
		services: BattleServices = null
) -> Dictionary:
	var result := {
		"node_count": 0,
		"projectile_count": 0,
		"effect_count": 0,
		"aircraft_squadron_count": 0,
		"fleet_ai_count": 0,
		"fleet_member_callback_count": 0,
		"pending_payload_release_count": 0,
		"pool_acquire_count": 0,
		"pool_release_count": 0,
		"pool_outstanding_count": 0,
		"pool_acquire_failure_count": 0,
		"pool_release_failure_count": 0,
		"instantiate_fallback_count": 0,
		"foreign_instance_release_count": 0,
	}
	if subtree_root != null and is_instance_valid(subtree_root):
		_visit_node(subtree_root, result)
	if services != null:
		var pool := services.projectile_pool
		result["pool_acquire_count"] = pool.pool_acquire_count
		result["pool_release_count"] = pool.pool_release_count
		result["pool_outstanding_count"] = \
			pool.get_pool_outstanding_count()
		result["pool_acquire_failure_count"] = \
			pool.pool_acquire_failure_count
		result["pool_release_failure_count"] = \
			pool.pool_release_failure_count
		result["instantiate_fallback_count"] = \
			pool.instantiate_fallback_count
		result["foreign_instance_release_count"] = \
			pool.foreign_instance_release_count
	return result


static func is_runtime_clean(snapshot: Dictionary) -> bool:
	return int(snapshot.get("projectile_count", 0)) == 0 \
		and int(snapshot.get("effect_count", 0)) == 0 \
		and int(snapshot.get("aircraft_squadron_count", 0)) == 0 \
		and int(snapshot.get("fleet_ai_count", 0)) == 0 \
		and int(snapshot.get("fleet_member_callback_count", 0)) == 0 \
		and int(snapshot.get("pending_payload_release_count", 0)) == 0 \
		and int(snapshot.get("pool_outstanding_count", 0)) == 0


static func _visit_node(node: Node, result: Dictionary) -> void:
	result["node_count"] = int(result["node_count"]) + 1
	if node is ProjectileBase or node is WeaponProjectileBase:
		result["projectile_count"] = int(result["projectile_count"]) + 1
	if node is PooledEffectBase and (node as PooledEffectBase).active:
		result["effect_count"] = int(result["effect_count"]) + 1
	if node is AircraftSquadron:
		result["aircraft_squadron_count"] = \
			int(result["aircraft_squadron_count"]) + 1
		var release_snapshot := (
			node as AircraftSquadron
		).get_release_debug_snapshot()
		result["pending_payload_release_count"] = \
			int(result["pending_payload_release_count"]) \
			+ int(release_snapshot.get("active_request_count", 0))
	if node is FleetAIController:
		result["fleet_ai_count"] = int(result["fleet_ai_count"]) + 1
		result["fleet_member_callback_count"] = \
			int(result["fleet_member_callback_count"]) \
			+ (node as FleetAIController).get_member_exit_callback_count()
	for child in node.get_children():
		_visit_node(child, result)
