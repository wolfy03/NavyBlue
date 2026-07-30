extends RefCounted
class_name BattleEnduranceMetrics

var samples: Array[Dictionary] = []
var warning_count := 0
var error_count := 0
var total_measured_frames := 0
var total_frame_time_msec := 0.0
var maximum_frame_time_msec := 0.0


func record_chunk_timing(frame_count: int, elapsed_msec: float) -> void:
	if frame_count <= 0:
		return
	var average_msec := elapsed_msec / float(frame_count)
	total_measured_frames += frame_count
	total_frame_time_msec += elapsed_msec
	maximum_frame_time_msec = maxf(maximum_frame_time_msec, average_msec)


func capture_chunk(
		tree: SceneTree,
		chunk_index: int,
		elapsed_sec: float,
		services: BattleServices = null
) -> Dictionary:
	var sample := {
		"chunk_index": chunk_index,
		"elapsed_sec": elapsed_sec,
		"ship_count": _group_count(tree, &"ships"),
		"aircraft_count": _group_count(tree, &"aircraft"),
		"squadron_count": _group_count(tree, &"aircraft_squadrons"),
		"projectile_count": _count_projectiles(tree),
		"effect_count": _count_active_effects(tree.root),
		"node_count": _count_nodes(tree.root),
		"pending_payload_requests": _count_pending_payload_requests(tree),
		"pool_acquire_count": (
			services.projectile_pool.acquire_count
			if services != null else 0
		),
		"pool_release_count": (
			services.projectile_pool.release_count
			if services != null else 0
		),
		"fleet_decision_count": _count_fleet_decisions(tree),
		"orphan_ai_target_count": _count_orphan_ai_targets(tree),
		"invalid_callback_count": _count_invalid_callbacks(tree),
		"warning_count": warning_count,
		"error_count": error_count,
	}
	samples.append(sample)
	return sample


func validate_bounded_growth(
		maximum_node_growth: int = 24,
		maximum_projectile_growth: int = 8,
		maximum_effect_growth: int = 8
) -> PackedStringArray:
	var failures := PackedStringArray()
	if samples.size() < 2:
		return failures
	var first: Dictionary = samples.front()
	var last: Dictionary = samples.back()
	if int(last["node_count"]) - int(first["node_count"]) \
			> maximum_node_growth:
		failures.append("Node count grew beyond the endurance budget.")
	if int(last["projectile_count"]) - int(first["projectile_count"]) \
			> maximum_projectile_growth:
		failures.append("Projectile count grew beyond the endurance budget.")
	if int(last["effect_count"]) - int(first["effect_count"]) \
			> maximum_effect_growth:
		failures.append("Effect count grew beyond the endurance budget.")
	if int(last["pending_payload_requests"]) > 0:
		failures.append("Payload release requests remained pending.")
	var pool_balance := int(last["pool_acquire_count"]) \
		- int(last["pool_release_count"])
	if abs(pool_balance - int(last["projectile_count"])) > 2:
		failures.append(
			"Projectile pool balance does not match live projectile count."
		)
	if int(last["orphan_ai_target_count"]) > 0:
		failures.append("Destroyed AI targets remained assigned.")
	if int(last["invalid_callback_count"]) > 0:
		failures.append("FleetAI callback registry contains stale entries.")
	if error_count > 0:
		failures.append("Errors were recorded during endurance execution.")
	return failures


func get_summary() -> Dictionary:
	if samples.is_empty():
		return {}
	var first: Dictionary = samples.front()
	var last: Dictionary = samples.back()
	return {
		"chunks": samples.size(),
		"first_node_count": int(first["node_count"]),
		"last_node_count": int(last["node_count"]),
		"node_growth": int(last["node_count"]) - int(first["node_count"]),
		"projectile_growth":
			int(last["projectile_count"]) - int(first["projectile_count"]),
		"effect_growth":
			int(last["effect_count"]) - int(first["effect_count"]),
		"pending_payload_requests": int(last["pending_payload_requests"]),
		"pool_balance":
			int(last["pool_acquire_count"]) - int(last["pool_release_count"]),
		"fleet_decision_count": int(last["fleet_decision_count"]),
		"orphan_ai_target_count": int(last["orphan_ai_target_count"]),
		"invalid_callback_count": int(last["invalid_callback_count"]),
		"average_frame_time_msec": (
			total_frame_time_msec / float(total_measured_frames)
			if total_measured_frames > 0 else 0.0
		),
		"maximum_chunk_average_frame_time_msec":
			maximum_frame_time_msec,
	}


func _group_count(tree: SceneTree, group: StringName) -> int:
	return tree.get_nodes_in_group(group).filter(
		func(node: Node) -> bool:
			return is_instance_valid(node) and not node.is_queued_for_deletion()
	).size()


func _count_projectiles(tree: SceneTree) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(&"projectile_root"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += node.get_child_count()
	return count


func _count_active_effects(node: Node) -> int:
	var count := 1 if node is PooledEffectBase \
		and (node as PooledEffectBase).active else 0
	for child in node.get_children():
		count += _count_active_effects(child)
	return count


func _count_fleet_decisions(tree: SceneTree) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(&"fleet_ai_controller"):
		var fleet := node as FleetAIController
		if fleet != null:
			count += fleet.fleet_evaluation_count
	return count


func _count_orphan_ai_targets(tree: SceneTree) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(&"ships"):
		var ship := node as ShipUnit
		if ship == null:
			continue
		var target := ship.get_ai_target() as ShipUnit
		if target != null and (
			not is_instance_valid(target)
			or not target.is_alive()
			or target.is_queued_for_deletion()
		):
			count += 1
	return count


func _count_invalid_callbacks(tree: SceneTree) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(&"fleet_ai_controller"):
		var fleet := node as FleetAIController
		if fleet == null:
			continue
		count += maxi(
			fleet.get_member_exit_callback_count()
				- fleet.get_members().size(),
			0
		)
	return count


func _count_pending_payload_requests(tree: SceneTree) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(&"aircraft_squadrons"):
		var squadron := node as AircraftSquadron
		if squadron == null:
			continue
		var payload := (
			squadron.payload_release_coordinator.get_debug_snapshot()
			if squadron.payload_release_coordinator != null
			else {}
		)
		count += (payload.get("active_request_ids", []) as Array).size()
	return count


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
