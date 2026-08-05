extends RefCounted
class_name PlayerDiveBombRun

# Drives a player-ordered dive bomb on a designated world point or ship.
#
# Target selection and attack planning are shared with the AI mission:
# DiveBombTargetResolver decides what to attack (explicit clicked ship first,
# then the nearest hostile ship inside the acquisition radius around the
# designation, then the position itself) and DiveBombAttackPlanner builds the
# squadron's single central attack solution, so an acquired ship is tracked
# and lead-predicted exactly like an AI strike. Once the dive commits the
# solution is locked: no retargeting, no swerving.

enum State {
	MOVING_TO_ENTRY,
	DIVING,
	DONE,
}

const EPSILON := 0.0001
const ENTRY_REPATH_INTERVAL_SEC := 0.25
const ENTRY_REPATH_THRESHOLD_M := 40.0
## Matches the AI mission's commit margin: the dive begins when the reference
## aircraft's distance to the intended impact equals the fixed trajectory's
## horizontal travel.
const DIVE_COMMIT_MARGIN_M := 8.0
## Extra slack on top of the trajectory travel below which the commit gate
## starts probing; beyond it the squadron just keeps flying to the waypoint.
const GATE_PROBE_SLACK_M := 400.0
## How far beyond the aim point the keep-closing waypoint is pushed when the
## waypoint is reached while the reference is still short of dive range.
const ENTRY_PUSH_THROUGH_M := 200.0

var state: State = State.DONE

var _squadron: AircraftSquadron
var _target_point := Vector3.ZERO
## Legacy scatter radius, used only by the solutionless fallback dive.
var _dispersion_radius_m := 0.0
var _target_request: DiveBombTargetRequest
var _resolved_target: DiveBombResolvedTarget
var _attack_context := DiveBombAttackContext.new()
var _destination_initialized := false
var _active_destination_serial := -1
var _entry_repath_left := 0.0
var _last_entry_position := Vector3.ZERO
var _reference_aircraft_ref: WeakRef
var _gate_probe_valid := false
var _gate_distance_m := 0.0
var _gate_required_travel_m := 0.0
var _gate_final_aim := Vector3.ZERO
var _gate_attack_direction := Vector3.FORWARD


func setup(
		squadron: AircraftSquadron,
		target_point: Vector3,
		dispersion_radius_m: float,
		explicit_target: ShipUnit = null
) -> bool:
	_squadron = squadron
	_target_point = target_point
	_dispersion_radius_m = maxf(dispersion_radius_m, 0.0)
	if _squadron == null or not is_instance_valid(_squadron) \
			or _squadron.dive_bomb_controller == null \
			or _get_dive_data() == null:
		state = State.DONE
		return false
	var dive_data := _get_dive_data()
	_target_request = DiveBombTargetRequest.new()
	_target_request.source = DiveBombTargetRequest.Source.PLAYER
	_target_request.set_explicit_target(explicit_target)
	_target_request.designated_world_position = target_point
	_target_request.acquisition_radius_m = \
		dive_data.get_target_acquisition_radius_m()
	_target_request.requesting_team = _squadron.get_team()
	_target_request.allow_position_fallback = true
	_attack_context = DiveBombAttackContext.new()
	_attack_context.squadron_combat_id = _squadron.get_instance_id()
	_attack_context.reset_for_new_pass()
	_resolve_target()
	if _resolved_target == null or not _resolved_target.is_valid():
		state = State.DONE
		return false
	state = State.MOVING_TO_ENTRY
	_destination_initialized = false
	_active_destination_serial = -1
	_entry_repath_left = 0.0
	return true


func update(delta: float) -> void:
	if is_finished() or _squadron == null or not is_instance_valid(_squadron):
		state = State.DONE
		return
	if state == State.MOVING_TO_ENTRY:
		_update_move_to_entry(delta)


func is_finished() -> bool:
	return state == State.DIVING or state == State.DONE


func cancel(_reason: StringName = &"") -> void:
	state = State.DONE


func get_resolved_target() -> DiveBombResolvedTarget:
	return _resolved_target


func get_debug_snapshot() -> Dictionary:
	var snapshot := {
		"state": State.keys()[int(state)],
		"designated_world_position":
			_target_request.designated_world_position \
			if _target_request != null else Vector3.ZERO,
		"target_acquisition_radius_m":
			_target_request.acquisition_radius_m \
			if _target_request != null else 0.0,
		"target_resolve_count": _attack_context.target_resolve_count,
		"target_reacquire_count": _attack_context.target_reacquire_count,
	}
	if _resolved_target != null:
		snapshot.merge(_resolved_target.get_debug_snapshot())
	return snapshot


## Resolver runs only at command receipt, entry repath ticks and target
## loss — never per physics frame, once for the whole squadron.
func _resolve_target() -> void:
	_attack_context.target_resolve_count += 1
	_resolved_target = DiveBombTargetResolver.resolve(
		_target_request,
		_squadron.get_dive_bomb_candidate_ships()
	)


func _update_move_to_entry(delta: float) -> void:
	# Approach-phase loss policy: search the designation again; a new hostile
	# ship becomes the target, otherwise the position fallback takes over.
	if _resolved_target.is_ship_target_lost():
		_attack_context.target_reacquire_count += 1
		_resolve_target()
	if not _resolved_target.is_valid():
		state = State.DONE
		return
	_entry_repath_left = maxf(_entry_repath_left - maxf(delta, 0.0), 0.0)
	if not _destination_initialized or _entry_repath_left <= 0.0:
		# Repath tick: re-confirm the target (a ship may have sailed into the
		# acquisition radius) and refresh the entry waypoint for its motion.
		_resolve_target()
		if not _resolved_target.is_valid():
			state = State.DONE
			return
		var next_entry := _calculate_entry_position()
		_entry_repath_left = ENTRY_REPATH_INTERVAL_SEC
		if not _destination_initialized \
				or _last_entry_position.distance_to(next_entry) \
					>= ENTRY_REPATH_THRESHOLD_M:
			_last_entry_position = next_entry
			_active_destination_serial = _squadron.set_mission_destination(
				next_entry,
				true
			)
			_destination_initialized = true
	# Same distance-gated commit as the AI mission: the dive begins at true
	# geometry, not at waypoint arrival.
	if _try_commit_on_distance_gate():
		return
	if not _squadron.has_reached_mission_destination(
		_active_destination_serial
	):
		return
	if _gate_probe_valid \
			and _gate_distance_m > _gate_required_travel_m \
				+ DIVE_COMMIT_MARGIN_M:
		# Waypoint reached while the reference aircraft still trails short of
		# dive range: push the waypoint through the aim point and keep
		# closing until the gate commits.
		var push_destination := _gate_final_aim \
			+ _gate_attack_direction * ENTRY_PUSH_THROUGH_M
		push_destination.y = _last_entry_position.y
		_last_entry_position = push_destination
		_active_destination_serial = _squadron.set_mission_destination(
			push_destination,
			true
		)
		_destination_initialized = true
		return
	_commit_dive()


## The pass's reference aircraft, cached while it survives (mirrors the AI
## mission's stability rule).
func _get_reference_aircraft() -> AircraftUnit:
	var current: Variant = _reference_aircraft_ref.get_ref() \
		if _reference_aircraft_ref != null else null
	if current != null and is_instance_valid(current):
		var aircraft := current as AircraftUnit
		if aircraft != null and aircraft.is_alive():
			return aircraft
	var selected := _squadron.select_dive_bomb_reference_aircraft()
	_reference_aircraft_ref = weakref(selected) if selected != null else null
	return selected


func _try_commit_on_distance_gate() -> bool:
	_gate_probe_valid = false
	var reference := _get_reference_aircraft()
	if reference == null:
		return false
	# Probe only near the target: far out, the plain distance check is enough
	# and the per-frame ballistic solve is skipped.
	if not _is_within_gate_probe_range(reference):
		return false
	var commit_solution := _build_commit_solution(reference)
	if commit_solution == null or not commit_solution.valid:
		return false
	var gate := DiveBombAttackPlanner.evaluate_commit_gate(
		reference.global_position,
		commit_solution,
		DIVE_COMMIT_MARGIN_M
	)
	_gate_probe_valid = true
	_gate_distance_m = gate["distance_m"]
	_gate_required_travel_m = gate["required_travel_m"]
	_gate_final_aim = gate["final_aim"]
	_gate_attack_direction = gate["attack_direction"]
	if not gate["should_commit"]:
		return false
	return _begin_dive_with_solution(commit_solution, reference)


func _is_within_gate_probe_range(reference: AircraftUnit) -> bool:
	var aim := _resolved_target.get_aim_position()
	var to_aim := aim - reference.global_position
	to_aim.y = 0.0
	var travel_estimate := _gate_required_travel_m \
		if _gate_required_travel_m > 0.0 else 0.0
	if travel_estimate <= 0.0:
		var dive_data := _get_dive_data()
		travel_estimate = maxf(
			dive_data.dive_entry_horizontal_distance_m,
			dive_data.dive_entry_altitude_m
		)
	return to_aim.length() <= travel_estimate + GATE_PROBE_SLACK_M


func _commit_dive() -> void:
	var controller := _squadron.dive_bomb_controller
	if controller == null:
		state = State.DONE
		return
	var reference := _get_reference_aircraft()
	var commit_solution := _build_commit_solution(reference) \
		if reference != null else null
	if commit_solution != null and commit_solution.valid:
		if _begin_dive_with_solution(commit_solution, reference):
			return
	# Solver failure (or no reference): the legacy point-based dive with the
	# preview's scatter radius keeps the order honored.
	var begin_result := controller.begin_dive_with_source(
		_resolved_target.get_aim_position(),
		_resolved_target.get_target_velocity(),
		AircraftSquadron.DiveControlSource.PLAYER,
		_dispersion_radius_m
	)
	if begin_result == DiveBombAttackController.BeginDiveResult.STARTED \
			or begin_result == DiveBombAttackController.BeginDiveResult \
				.ALREADY_ACTIVE_SAME_SOURCE:
		state = State.DIVING
	else:
		state = State.DONE


func _begin_dive_with_solution(
		solution: DiveBombAttackSolution,
		reference: AircraftUnit
) -> bool:
	var controller := _squadron.dive_bomb_controller
	var begin_result := controller.begin_dive_with_solution(
		solution,
		AircraftSquadron.DiveControlSource.PLAYER,
		0.0,
		reference
	)
	match begin_result:
		DiveBombAttackController.BeginDiveResult.STARTED, \
				DiveBombAttackController.BeginDiveResult \
					.ALREADY_ACTIVE_SAME_SOURCE:
			# The player dive commits here and now: lock the solution so the
			# committed trajectory can never be dragged around afterwards.
			controller.lock_solution()
			state = State.DIVING
			return true
	state = State.DONE
	return false


func _build_commit_solution(
		reference: AircraftUnit
) -> DiveBombAttackSolution:
	return DiveBombAttackPlanner.build_commit_solution(
		_squadron,
		reference,
		_resolved_target,
		_get_dive_data(),
		_squadron.get_aircraft_weapon_data(),
		_attack_context
	)


## Entry waypoint: the release point's ground track at entry altitude (same
## fly-through rule as the AI mission), from the planner's full solve. Falls
## back to the fixed-angle geometric entry when the solver fails.
func _calculate_entry_position() -> Vector3:
	var navigation_solution := DiveBombAttackPlanner.build_navigation_solution(
		_squadron,
		_get_reference_aircraft(),
		_resolved_target,
		_get_dive_data(),
		_squadron.get_aircraft_weapon_data(),
		true,
		_attack_context
	)
	if navigation_solution != null and navigation_solution.valid:
		var next_entry := navigation_solution.release_position
		next_entry.y = navigation_solution.dive_entry_position.y
		return next_entry
	var dive_data := _get_dive_data()
	var aim := _resolved_target.get_aim_position()
	var height := maxf(dive_data.dive_entry_altitude_m, 1.0)
	var tangent := tan(deg_to_rad(clampf(
		dive_data.dive_angle_degrees,
		1.0,
		89.0
	)))
	var horizontal_distance := (
		dive_data.dive_entry_horizontal_distance_m
		if dive_data.dive_entry_horizontal_distance_m > 0.0
		else height / maxf(tangent, 0.01)
	)
	var direction := DiveBombAttackPlanner.get_attack_direction(
		_squadron,
		aim
	)
	var result := aim - direction * horizontal_distance
	result.y = aim.y + height
	return result


func _get_dive_data() -> DiveBomberCombatData:
	return _squadron.get_dive_bomber_combat_data() \
		if _squadron != null and is_instance_valid(_squadron) else null
