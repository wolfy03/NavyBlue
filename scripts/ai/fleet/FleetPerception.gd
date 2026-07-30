extends RefCounted
class_name FleetPerception


func collect_snapshot(
		own_units: Array[ShipUnit],
		enemy_units: Array[ShipUnit],
		fleet_center: Vector3,
		assignment_tracker: FleetTargetAssignmentTracker,
		emergency_target_ids: Dictionary
) -> FleetPerceptionSnapshot:
	var snapshot := FleetPerceptionSnapshot.new()
	snapshot.own_units = own_units.duplicate()
	snapshot.fleet_center = fleet_center
	for candidate in enemy_units:
		if candidate == null or not is_instance_valid(candidate) \
				or candidate.is_queued_for_deletion() \
				or not candidate.is_alive():
			continue
		var observation := FleetUnitObservation.new()
		observation.ship_ref = weakref(candidate)
		observation.distance_m = fleet_center.distance_to(
			candidate.global_position
		)
		observation.strategic_value = candidate.ship_data.strategic_value \
			if candidate.ship_data != null else 1.0
		if candidate.combat != null:
			observation.sustained_dps = \
				candidate.combat.get_total_sustained_dps()
			observation.ready_salvo_damage = \
				candidate.combat.get_total_ready_salvo_damage()
			observation.torpedo_salvo_damage = \
				candidate.combat.get_total_salvo_damage(
					WeaponTypes.Type.TORPEDO
				)
			observation.cannon_sustained_dps = \
				candidate.combat.get_total_sustained_dps(
					WeaponTypes.Type.CANNON
				)
		observation.assigned_attacker_count = \
			assignment_tracker.get_attacker_count(candidate) \
			if assignment_tracker != null else 0
		observation.emergency = emergency_target_ids.has(
			candidate.get_instance_id()
		)
		snapshot.observations.append(observation)
	return snapshot
