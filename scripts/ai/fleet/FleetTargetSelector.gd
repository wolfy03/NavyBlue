extends RefCounted
class_name FleetTargetSelector


func rank_targets(
		snapshot: FleetPerceptionSnapshot,
		settings: FleetAISettings,
		current_primary: ShipUnit,
		current_target_bonus: float
) -> Array[FleetUnitObservation]:
	var ranked: Array[FleetUnitObservation] = []
	if snapshot == null or settings == null:
		return ranked
	for observation in snapshot.observations:
		var ship := observation.get_ship()
		if ship == null:
			continue
		var distance_score := settings.distance_score_weight * maxf(
			1.0 - observation.distance_m / settings.distance_reference_m,
			0.0
		)
		observation.raw_score = \
			observation.strategic_value * settings.strategic_value_weight \
			+ minf(
				observation.sustained_dps / settings.sustained_dps_divisor,
				settings.sustained_dps_cap
			) \
			+ minf(
				observation.ready_salvo_damage \
					/ settings.ready_salvo_divisor,
				settings.salvo_score_cap
			) \
			+ minf(
				observation.torpedo_salvo_damage \
					/ settings.torpedo_salvo_divisor,
				settings.salvo_score_cap
			) \
			+ distance_score
		if observation.emergency:
			observation.raw_score += settings.emergency_bonus
		observation.raw_score -= float(
			observation.assigned_attacker_count
		) * settings.duplicate_assignment_penalty
		observation.selection_score = observation.raw_score
		if ship == current_primary:
			observation.selection_score += current_target_bonus
		ranked.append(observation)
	ranked.sort_custom(_sort_observations)
	return ranked


func _sort_observations(
		first: FleetUnitObservation,
		second: FleetUnitObservation
) -> bool:
	if not is_equal_approx(
		first.selection_score,
		second.selection_score
	):
		return first.selection_score > second.selection_score
	var first_ship := first.get_ship()
	var second_ship := second.get_ship()
	if first_ship == null:
		return false
	if second_ship == null:
		return true
	return first_ship.get_instance_id() < second_ship.get_instance_id()
