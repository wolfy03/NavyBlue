extends RefCounted
class_name BattleEnduranceMetrics

var samples: Array[Dictionary] = []
var warning_count := 0
var error_count := 0
var total_measured_frames := 0
var total_frame_time_msec := 0.0
var maximum_frame_time_msec := 0.0

var profile_name: StringName = EnduranceProfile.SMOKE
var seed := 1
var total_requested_frames := 0
var total_executed_frames := 0
var chunk_size_frames := EnduranceProfile.DEFAULT_CHUNK_SIZE_FRAMES
var combat_chunk_count := 0
var cleanup_chunk_count := 0
var initial_snapshot_count := 0
var final_snapshot_count := 0
var warmup_frames := EnduranceProfile.DEFAULT_WARMUP_FRAMES
var cleanup_frames := EnduranceProfile.DEFAULT_CLEANUP_FRAMES
var baseline: Dictionary = {}
var active_peak: Dictionary = {}
var post_cleanup_final: Dictionary = {}


func configure(
		next_profile_name: StringName,
		next_seed: int,
		next_warmup_frames: int,
		next_cleanup_frames: int
) -> void:
	profile_name = next_profile_name
	seed = next_seed
	warmup_frames = maxi(next_warmup_frames, 0)
	cleanup_frames = maxi(next_cleanup_frames, 0)


func record_chunk_timing(frame_count: int, elapsed_msec: float) -> void:
	if frame_count <= 0:
		return
	var average_msec := elapsed_msec / float(frame_count)
	total_measured_frames += frame_count
	total_frame_time_msec += elapsed_msec
	maximum_frame_time_msec = maxf(maximum_frame_time_msec, average_msec)


func capture_baseline(
		tree: SceneTree,
		services: BattleServices = null
) -> Dictionary:
	baseline = _capture_snapshot(tree, &"baseline", services)
	active_peak = baseline.duplicate(true)
	initial_snapshot_count += 1
	return baseline


func capture_chunk(
		tree: SceneTree,
		chunk_index: int,
		elapsed_sec: float,
		services: BattleServices = null
) -> Dictionary:
	var sample := _capture_snapshot(tree, &"active", services)
	sample["chunk_index"] = chunk_index
	sample["elapsed_sec"] = elapsed_sec
	samples.append(sample)
	_update_active_peak(sample)
	return sample


func capture_post_cleanup(
		tree: SceneTree,
		services: BattleServices = null
) -> Dictionary:
	post_cleanup_final = _capture_snapshot(
		tree,
		&"post_cleanup",
		services
	)
	final_snapshot_count += 1
	cleanup_chunk_count += 1
	return post_cleanup_final


func validate_metadata() -> PackedStringArray:
	return EnduranceResultMetadata.validate(
		total_requested_frames,
		total_executed_frames,
		chunk_size_frames,
		combat_chunk_count,
		samples.size()
	)


func validate_bounded_growth(
		maximum_node_growth: int = 24,
		maximum_projectile_growth: int = 8,
		maximum_effect_growth: int = 8
) -> PackedStringArray:
	var failures := PackedStringArray()
	if baseline.is_empty() or active_peak.is_empty():
		return failures
	if int(active_peak["node_count"]) - int(baseline["node_count"]) \
			> maximum_node_growth:
		failures.append("Node count grew beyond the endurance budget.")
	if int(active_peak["active_projectiles"]) \
			- int(baseline["active_projectiles"]) \
			> maximum_projectile_growth:
		failures.append("Projectile count grew beyond the endurance budget.")
	if int(active_peak["active_effects"]) \
			- int(baseline["active_effects"]) \
			> maximum_effect_growth:
		failures.append("Effect count grew beyond the endurance budget.")
	if error_count > 0:
		failures.append("Errors were recorded during endurance execution.")
	return failures


func validate_cleanup() -> PackedStringArray:
	var failures := PackedStringArray()
	if post_cleanup_final.is_empty():
		failures.append("Post-cleanup metrics were not captured.")
		return failures
	for metric_name in [
		"active_projectiles",
		"active_effects",
		"pending_payload_requests",
		"orphan_ai_target_count",
		"invalid_callback_count",
		"pool_outstanding_count",
		"pool_active_lease_count",
		"active_presentation_binding_count",
		"active_selection_box_count",
		"active_command_path_count",
		"active_status_overlay_count",
		"processing_presenter_count",
	]:
		if int(post_cleanup_final.get(metric_name, 0)) != 0:
			failures.append(
				"Post-cleanup metric '%s' must be zero." % metric_name
			)
	return failures


func get_summary() -> Dictionary:
	var summary := EnduranceResultMetadata.build_summary(
		profile_name,
		seed,
		total_requested_frames,
		total_executed_frames,
		chunk_size_frames,
		samples.size(),
		combat_chunk_count,
		cleanup_chunk_count,
		initial_snapshot_count,
		final_snapshot_count,
		warmup_frames,
		cleanup_frames
	)
	summary.merge({
		"baseline": baseline,
		"active_peak": active_peak,
		"post_cleanup_final": post_cleanup_final,
		"average_frame_time_msec": (
			total_frame_time_msec / float(total_measured_frames)
			if total_measured_frames > 0 else 0.0
		),
		"maximum_chunk_average_frame_time_msec":
			maximum_frame_time_msec,
	})
	return summary


func _capture_snapshot(
		tree: SceneTree,
		phase: StringName,
		services: BattleServices
) -> Dictionary:
	var pool := services.projectile_pool \
		if services != null else null
	var snapshot := {
		"phase": phase,
		"ship_count": _group_count(tree, &"ships"),
		"aircraft_count": _group_count(tree, &"aircraft"),
		"squadron_count": _group_count(tree, &"aircraft_squadrons"),
		"active_projectiles": _count_active_projectiles(tree),
		"pooled_projectiles": _count_pooled_projectiles(tree.root),
		"active_effects": _count_active_effects(tree.root),
		"pooled_effects": _count_pooled_effects(tree.root),
		"node_count": _count_nodes(tree.root),
		"pending_payload_requests": _count_pending_payload_requests(tree),
		"pool_acquire_count": pool.pool_acquire_count \
			if pool != null else 0,
		"pool_release_count": pool.pool_release_count \
			if pool != null else 0,
		"pool_outstanding_count": pool.get_pool_outstanding_count() \
			if pool != null else 0,
		"pool_active_lease_count": pool.get_active_pool_lease_count() \
			if pool != null else 0,
		"pool_acquire_failure_count": pool.pool_acquire_failure_count \
			if pool != null else 0,
		"pool_release_failure_count": pool.pool_release_failure_count \
			if pool != null else 0,
		"instantiate_fallback_count": pool.instantiate_fallback_count \
			if pool != null else 0,
		"foreign_instance_release_count": pool.foreign_instance_release_count \
			if pool != null else 0,
		"factory_instance_release_count": pool.factory_instance_release_count \
			if pool != null else 0,
		"legacy_direct_pool_release_count":
			pool.legacy_direct_pool_release_count if pool != null else 0,
		"orphan_ai_target_count": _count_orphan_ai_targets(tree),
		"invalid_callback_count": _count_invalid_callbacks(tree),
		"warning_count": warning_count,
		"error_count": error_count,
	}
	snapshot.merge(_capture_fleet_decision_metrics(tree))
	snapshot.merge(_capture_aircraft_presentation_metrics(tree))
	return snapshot


func _update_active_peak(sample: Dictionary) -> void:
	active_peak["phase"] = &"active_peak"
	for metric_name in [
		"node_count",
		"active_projectiles",
		"pooled_projectiles",
		"active_effects",
		"pooled_effects",
		"pending_payload_requests",
		"pool_outstanding_count",
		"pool_active_lease_count",
		"pool_acquire_count",
		"pool_release_count",
		"pool_acquire_failure_count",
		"pool_release_failure_count",
		"instantiate_fallback_count",
		"foreign_instance_release_count",
		"factory_instance_release_count",
		"legacy_direct_pool_release_count",
		"active_presentation_binding_count",
		"active_selection_box_count",
		"active_command_path_count",
		"active_status_overlay_count",
		"processing_presenter_count",
		"fleet_decision_count",
		"perception_refresh_count",
		"target_evaluation_count",
		"primary_target_change_count",
		"role_assignment_count",
		"tactical_plan_count",
		"member_order_dispatch_count",
		"emergency_assignment_count",
		"invalid_decision_count",
		"empty_decision_count",
	]:
		active_peak[metric_name] = maxi(
			int(active_peak.get(metric_name, 0)),
			int(sample.get(metric_name, 0))
		)


func _capture_aircraft_presentation_metrics(
		tree: SceneTree
) -> Dictionary:
	var result := {
		"active_presentation_binding_count": 0,
		"active_selection_box_count": 0,
		"active_command_path_count": 0,
		"active_status_overlay_count": 0,
		"processing_presenter_count": 0,
	}
	if tree == null:
		return result
	for node in tree.get_nodes_in_group(
		&"aircraft_command_presentations"
	):
		var presentation := node as AircraftCommandPresentation
		if presentation == null or not is_instance_valid(presentation):
			continue
		var snapshot := presentation.get_debug_snapshot()
		result["active_presentation_binding_count"] += int(
			snapshot.get("active_binding_count", 0)
		)
		result["active_selection_box_count"] += int(
			snapshot.get("active_selection_box_count", 0)
		)
		result["active_command_path_count"] += int(
			snapshot.get("active_path_count", 0)
		)
		result["active_status_overlay_count"] += int(
			snapshot.get("active_overlay_count", 0)
		)
		result["processing_presenter_count"] += int(
			snapshot.get("processing_presenter_count", 0)
		)
	return result


func _group_count(tree: SceneTree, group: StringName) -> int:
	return tree.get_nodes_in_group(group).filter(
		func(node: Node) -> bool:
			return is_instance_valid(node) and not node.is_queued_for_deletion()
	).size()


func _count_active_projectiles(tree: SceneTree) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(&"projectile_root"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		for child in node.get_children():
			if (child is ProjectileBase or child is WeaponProjectileBase) \
					and not bool(child.get_meta(&"in_object_pool", false)):
				count += 1
	return count


func _count_pooled_projectiles(node: Node) -> int:
	var count := 1 if (
		(node is ProjectileBase or node is WeaponProjectileBase)
		and bool(node.get_meta(&"in_object_pool", false))
	) else 0
	for child in node.get_children():
		count += _count_pooled_projectiles(child)
	return count


func _count_active_effects(node: Node) -> int:
	var count := 1 if node is PooledEffectBase \
		and (node as PooledEffectBase).active else 0
	for child in node.get_children():
		count += _count_active_effects(child)
	return count


func _count_pooled_effects(node: Node) -> int:
	var count := 1 if node is PooledEffectBase \
		and not (node as PooledEffectBase).active else 0
	for child in node.get_children():
		count += _count_pooled_effects(child)
	return count


func _capture_fleet_decision_metrics(tree: SceneTree) -> Dictionary:
	var metrics := {
		"fleet_decision_count": 0,
		"perception_refresh_count": 0,
		"target_evaluation_count": 0,
		"primary_target_change_count": 0,
		"role_assignment_count": 0,
		"tactical_plan_count": 0,
		"member_order_dispatch_count": 0,
		"emergency_assignment_count": 0,
		"invalid_decision_count": 0,
		"empty_decision_count": 0,
	}
	for node in tree.get_nodes_in_group(&"fleet_ai_controller"):
		var fleet := node as FleetAIController
		if fleet != null:
			metrics["fleet_decision_count"] += fleet.fleet_evaluation_count
			metrics["perception_refresh_count"] += \
				fleet.perception_refresh_count
			metrics["target_evaluation_count"] += \
				fleet.target_evaluation_count
			metrics["primary_target_change_count"] += \
				fleet.primary_target_change_count
			metrics["role_assignment_count"] += fleet.role_assignment_count
			metrics["tactical_plan_count"] += fleet.tactical_plan_count
			metrics["member_order_dispatch_count"] += \
				fleet.member_order_dispatch_count
			metrics["emergency_assignment_count"] += \
				fleet.emergency_assignment_count
			metrics["invalid_decision_count"] += \
				fleet.invalid_decision_count
			metrics["empty_decision_count"] += fleet.empty_decision_count
	return metrics


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
