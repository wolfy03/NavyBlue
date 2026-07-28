extends Node
class_name AircraftCombatCoordinator

var _registered_squadrons: Array[AircraftSquadron] = []
var _intercept_assignments: Dictionary = {}
var _last_candidate_count := 0


func _ready() -> void:
	add_to_group(&"aircraft_combat_coordinator")


func register_squadron(squadron: AircraftSquadron) -> void:
	_prune_invalid_squadrons()
	if squadron == null or not is_instance_valid(squadron) \
			or _registered_squadrons.has(squadron):
		return
	_registered_squadrons.append(squadron)


func unregister_squadron(squadron: AircraftSquadron) -> void:
	if squadron == null:
		return
	_registered_squadrons.erase(squadron)
	unregister_intercept_assignment(squadron)
	var removed_id := squadron.get_instance_id() \
		if is_instance_valid(squadron) else 0
	for attacker_id in _intercept_assignments.keys().duplicate():
		var assignment := _intercept_assignments[attacker_id] as Dictionary
		var target := _get_assignment_squadron(assignment, &"target")
		if target == null \
				or not is_instance_valid(target) \
				or target.get_instance_id() == removed_id:
			_intercept_assignments.erase(attacker_id)


func get_hostile_squadrons(
		requester_team: StringName
) -> Array[AircraftSquadron]:
	_prune_invalid_squadrons()
	var result: Array[AircraftSquadron] = []
	for squadron in _registered_squadrons:
		if _is_valid_target_squadron(squadron) \
				and FactionRelations.are_hostile(
					requester_team,
					squadron.get_team()
				):
			result.append(squadron)
	return result


func find_best_intercept_target(
		requester: AircraftSquadron,
		origin: Vector3,
		maximum_range_m: float
) -> AircraftSquadron:
	if requester == null or not is_instance_valid(requester):
		return null
	return find_best_intercept_target_for_team(
		requester.get_team(),
		origin,
		maximum_range_m,
		requester.get_fighter_combat_data()
	)


func find_best_intercept_target_for_team(
		requester_team: StringName,
		origin: Vector3,
		maximum_range_m: float,
		fighter_data: FighterCombatData = null,
		maximum_assignments: int = 0
) -> AircraftSquadron:
	_last_candidate_count = 0
	var best_target: AircraftSquadron
	var best_score := -INF
	for candidate in get_hostile_squadrons(requester_team):
		var distance := origin.distance_to(candidate.formation_center)
		if maximum_range_m > 0.0 and distance > maximum_range_m:
			continue
		if maximum_assignments > 0 \
				and get_interceptor_count_for(candidate) \
					>= maximum_assignments:
			continue
		_last_candidate_count += 1
		var score := _score_target(
			candidate,
			distance,
			maximum_range_m,
			fighter_data
		)
		if best_target == null \
				or score > best_score \
				or (
					is_equal_approx(score, best_score)
					and candidate.get_instance_id()
						< best_target.get_instance_id()
				):
			best_target = candidate
			best_score = score
	return best_target


func register_intercept_assignment(
		attacker: AircraftSquadron,
		target: AircraftSquadron
) -> void:
	if attacker == null or target == null \
			or not is_instance_valid(attacker) \
			or not is_instance_valid(target):
		return
	_intercept_assignments[attacker.get_instance_id()] = {
		"attacker": weakref(attacker),
		"target": weakref(target),
	}


func unregister_intercept_assignment(
		attacker: AircraftSquadron
) -> void:
	if attacker != null and is_instance_valid(attacker):
		_intercept_assignments.erase(attacker.get_instance_id())


func get_interceptor_count_for(
		target: AircraftSquadron
) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	_prune_assignments()
	var count := 0
	for assignment_value in _intercept_assignments.values():
		var assignment := assignment_value as Dictionary
		if _get_assignment_squadron(assignment, &"target") == target:
			count += 1
	return count


func get_debug_snapshot() -> Dictionary:
	_prune_invalid_squadrons()
	_prune_assignments()
	var team_counts: Dictionary = {}
	for squadron in _registered_squadrons:
		var key := String(squadron.get_team())
		team_counts[key] = int(team_counts.get(key, 0)) + 1
	var assignments: Dictionary = {}
	for attacker_id in _intercept_assignments:
		var assignment := _intercept_assignments[attacker_id] as Dictionary
		var target := _get_assignment_squadron(assignment, &"target")
		assignments[str(attacker_id)] = target.name \
			if target != null and is_instance_valid(target) else ""
	return {
		"registered_squadron_count": _registered_squadrons.size(),
		"team_squadron_counts": team_counts,
		"intercept_assignments": assignments,
		"candidate_count": _last_candidate_count,
	}


func _score_target(
		target: AircraftSquadron,
		distance_m: float,
		maximum_range_m: float,
		fighter_data: FighterCombatData
) -> float:
	var distance_score := (
		1.0 - clampf(
			distance_m / maxf(maximum_range_m, 1.0),
			0.0,
			1.0
		)
	) * 100.0 * (
		fighter_data.distance_weight if fighter_data != null else 1.0
	)
	var role_bonus := 0.0
	match target.get_aircraft_role():
		AircraftData.AircraftRole.TORPEDO_BOMBER:
			role_bonus = fighter_data.torpedo_bomber_priority_bonus \
				if fighter_data != null else 45.0
		AircraftData.AircraftRole.DIVE_BOMBER:
			role_bonus = fighter_data.bomber_priority_bonus \
				if fighter_data != null else 35.0
		AircraftData.AircraftRole.FIGHTER:
			role_bonus = fighter_data.fighter_priority_bonus \
				if fighter_data != null else 10.0
		AircraftData.AircraftRole.RECON:
			role_bonus = 5.0
	var duplicate_penalty := get_interceptor_count_for(target) * (
		fighter_data.duplicate_target_penalty \
		if fighter_data != null else 20.0
	)
	return distance_score \
		+ role_bonus \
		+ float(target.get_alive_aircraft_count()) * 2.0 \
		- duplicate_penalty


func _is_valid_target_squadron(squadron: AircraftSquadron) -> bool:
	return squadron != null \
		and is_instance_valid(squadron) \
		and not squadron.is_queued_for_deletion() \
		and squadron.state not in [
			AircraftSquadron.State.RETURNING,
			AircraftSquadron.State.RECOVERING,
			AircraftSquadron.State.DESTROYED,
		] \
		and squadron.get_alive_aircraft_count() > 0


func _prune_invalid_squadrons() -> void:
	for index in range(_registered_squadrons.size() - 1, -1, -1):
		var squadron := _registered_squadrons[index]
		if squadron == null or not is_instance_valid(squadron) \
				or squadron.is_queued_for_deletion():
			_registered_squadrons.remove_at(index)
	_prune_assignments()


func _prune_assignments() -> void:
	for attacker_id in _intercept_assignments.keys().duplicate():
		var assignment := _intercept_assignments[attacker_id] as Dictionary
		var attacker := _get_assignment_squadron(
			assignment,
			&"attacker"
		)
		var target := _get_assignment_squadron(assignment, &"target")
		if not _is_valid_assignment_member(attacker) \
				or not _is_valid_assignment_member(target):
			_intercept_assignments.erase(attacker_id)


func _get_assignment_squadron(
		assignment: Dictionary,
		key: StringName
) -> AircraftSquadron:
	var ref := assignment.get(key) as WeakRef
	return ref.get_ref() as AircraftSquadron if ref != null else null


func _is_valid_assignment_member(
		squadron: AircraftSquadron
) -> bool:
	return squadron != null \
		and is_instance_valid(squadron) \
		and not squadron.is_queued_for_deletion() \
		and squadron.state not in [
			AircraftSquadron.State.RETURNING,
			AircraftSquadron.State.RECOVERING,
			AircraftSquadron.State.DESTROYED,
		]
