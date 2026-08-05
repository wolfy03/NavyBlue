extends RefCounted
class_name DiveBombMissionBehavior
## AI dive-bomb mission lifecycle: state transitions from approach through
## dive, egress and return.
##
## Everything else is delegated:
##   what to attack        -> DiveBombTargetResolver (via the squadron's
##                            candidate supply)
##   how to plan the pass  -> DiveBombAttackPlanner (accuracy, reference
##                            anchoring, resolver argument assembly)
##   pure ballistics       -> DiveBombAttackResolver
##   flying the dive       -> DiveBombAttackController

enum State {
	APPROACHING,
	DIVE_ENTRY,
	DIVING,
	PULLING_OUT,
	EGRESS,
	RETURNING,
	COMPLETED,
	FAILED,
}

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var mission_data: AirMissionData
var state: State = State.FAILED
var successful := false

## Legacy mirror of the resolved ship for get_target_ship() consumers and
## older tests that assign it directly; the resolver output is authoritative.
var _target_ref: WeakRef
var _finished := true
var _destination_initialized := false
var _last_approach_position := Vector3.ZERO
var _last_dive_entry_position := Vector3.ZERO
var _approach_repath_left := 0.0
var _current_mission_destination := Vector3.ZERO
var _active_destination_serial := -1
## Current attack geometry, solved backwards from the bomb impact point.
var _attack_solution: DiveBombAttackSolution

## Target selection state: the standing question and its current answer.
var _target_request: DiveBombTargetRequest
var _resolved_target: DiveBombResolvedTarget
## Per-pass planning state (deterministic dispersion, revisions, counters).
var _attack_context := DiveBombAttackContext.new()
var _dive_entry_reacquire_used := false

## Central reference aircraft for this attack pass. Selected once per pass and
## kept while it survives; only its loss triggers a reselection.
var _reference_aircraft_ref: WeakRef
var _reference_aircraft_instance_id := 0

const DIVE_ENTRY_REPATH_INTERVAL_SEC := 0.25
const DIVE_ENTRY_REPATH_THRESHOLD_M := 40.0
## Kept tighter than release_impact_trigger_margin_m: on a fixed dive path
## the predicted impact barely moves (the shorter bomb fall almost exactly
## cancels the aircraft's advance), so the commit moment IS the accuracy
## control and must land inside the release window's tolerance.
const DIVE_COMMIT_MARGIN_M := 8.0

var _dive_entry_repath_left := 0.0

## Last distance-gate probe, for the arrival fallback: when the waypoint is
## reached but the reference aircraft is still short of dive range, the
## destination is pushed further along the attack line instead of committing
## a dive whose fixed trajectory could never reach the aim point.
var _gate_probe_valid := false
var _gate_distance_m := 0.0
var _gate_required_travel_m := 0.0
var _gate_final_aim := Vector3.ZERO
var _gate_attack_direction := Vector3.FORWARD

## How far beyond the aim point the keep-closing waypoint is pushed.
const DIVE_ENTRY_PUSH_THROUGH_M := 200.0


## The pass's reference aircraft. Reselects only when the current one is gone,
## and forces an early repath so the solution is recomputed once for the new
## center — never per frame.
func _get_reference_aircraft() -> AircraftUnit:
	var current: Variant = _reference_aircraft_ref.get_ref() \
		if _reference_aircraft_ref != null else null
	if current != null and is_instance_valid(current):
		var aircraft := current as AircraftUnit
		if aircraft != null and aircraft.is_alive():
			return aircraft
	var selected := owner_squadron.select_dive_bomb_reference_aircraft() \
		if owner_squadron != null else null
	var previous_id := _reference_aircraft_instance_id
	_reference_aircraft_ref = weakref(selected) if selected != null else null
	_reference_aircraft_instance_id = selected.get_instance_id() \
		if selected != null else 0
	if selected != null and previous_id != 0 \
			and previous_id != _reference_aircraft_instance_id:
		# Reference lost mid-pass: recompute the solution once from the new
		# center by letting the next approach update repath immediately.
		_approach_repath_left = 0.0
	return selected


func setup(
		next_owner_squadron: AircraftSquadron,
		target_ship: Node3D,
		next_mission_data: AirMissionData
) -> bool:
	owner_squadron = next_owner_squadron
	mission_data = next_mission_data
	if not _is_valid_setup(target_ship):
		return false
	return setup_with_request(
		next_owner_squadron,
		_build_request_for_ship(target_ship as ShipUnit),
		next_mission_data
	)


## Request-based entry point: also usable for AI world-position strike orders
## (the request then carries no explicit ship).
func setup_with_request(
		next_owner_squadron: AircraftSquadron,
		request: DiveBombTargetRequest,
		next_mission_data: AirMissionData
) -> bool:
	owner_squadron = next_owner_squadron
	mission_data = next_mission_data
	if request == null or not _is_valid_squadron_setup():
		return false
	_target_request = request
	_attack_context = DiveBombAttackContext.new()
	_attack_context.squadron_combat_id = owner_squadron.get_instance_id()
	# One deterministic accuracy roll per attack pass: the planner rolls it
	# lazily AFTER the target is resolved and keeps it constant through every
	# re-solve of this pass.
	_attack_context.reset_for_new_pass()
	_resolve_target()
	if _resolved_target == null or not _resolved_target.is_valid():
		return false
	state = State.APPROACHING
	successful = false
	_finished = false
	_destination_initialized = false
	_dive_entry_reacquire_used = false
	_last_approach_position = Vector3.ZERO
	_last_dive_entry_position = Vector3.ZERO
	_approach_repath_left = 0.0
	_current_mission_destination = Vector3.ZERO
	_active_destination_serial = -1
	return true


func update(delta: float) -> void:
	if _finished or owner_squadron == null \
			or not is_instance_valid(owner_squadron):
		return
	_adopt_legacy_target_ref()
	if not _refresh_target_for_state():
		return
	match state:
		State.APPROACHING:
			_update_approaching(delta)
		State.DIVE_ENTRY:
			_update_dive_entry(delta)
		State.DIVING:
			_update_diving()
		State.PULLING_OUT:
			_update_pulling_out()
		State.EGRESS:
			_update_egress()
		State.RETURNING, State.COMPLETED, State.FAILED:
			pass


func cancel_and_return() -> void:
	if _finished:
		return
	_cancel_dive()
	_finish_and_return(false)


func cancel_without_return() -> void:
	if _finished:
		return
	_cancel_dive()
	successful = false
	_finished = true
	state = State.FAILED
	_target_ref = null
	_resolved_target = null


func get_state() -> int:
	return int(state)


func is_finished() -> bool:
	return _finished


func get_target_ship() -> Node3D:
	return _get_target_ship()


func get_resolved_target() -> DiveBombResolvedTarget:
	return _resolved_target


func get_debug_snapshot() -> Dictionary:
	var controller_state := "MISSING"
	var controller_result := {}
	var target_locked := false
	if owner_squadron != null and is_instance_valid(owner_squadron) \
			and owner_squadron.dive_bomb_controller != null:
		var controller := owner_squadron.dive_bomb_controller
		controller_state = DiveBombAttackController.State.keys()[
			int(controller.state)
		]
		controller_result = controller.get_attack_result_data().to_dictionary()
		target_locked = controller.is_solution_locked() \
			or state in [State.DIVING, State.PULLING_OUT]
	var target := _get_target_ship()
	return {
		"state": State.keys()[int(state)],
		"target_ship": target.name if target != null else "",
		"destination_initialized": _destination_initialized,
		"approach_position": _last_approach_position,
		"approach_repath_timer": _approach_repath_left,
		"active_destination_serial": _active_destination_serial,
		"dive_entry_position": _last_dive_entry_position,
		"mission_destination_reached":
			owner_squadron.has_reached_mission_destination() \
			if owner_squadron != null \
			and is_instance_valid(owner_squadron) else false,
		"controller_state": controller_state,
		"controller_result": controller_result,
		"target_locked": target_locked,
	}.merged(_get_target_debug_snapshot()) \
		.merged(_get_solution_debug_snapshot())


## Target-selection diagnostics: request, resolution and lock policy state.
func _get_target_debug_snapshot() -> Dictionary:
	var snapshot := {
		"target_request_source":
			DiveBombTargetRequest.Source.keys()[int(_target_request.source)] \
			if _target_request != null else "",
		"designated_world_position":
			_target_request.designated_world_position \
			if _target_request != null else Vector3.ZERO,
		"explicit_target_id":
			_target_request.get_explicit_target().get_instance_id() \
			if _target_request != null \
			and _target_request.get_explicit_target() != null else 0,
		"target_acquisition_radius_m":
			_target_request.acquisition_radius_m \
			if _target_request != null else 0.0,
		"target_resolve_count": _attack_context.target_resolve_count,
		"target_reacquire_count": _attack_context.target_reacquire_count,
	}
	if _resolved_target != null:
		snapshot.merge(_resolved_target.get_debug_snapshot())
	return snapshot


## Central-solution diagnostics: reference aircraft identity and the current
## attack geometry. Dictionary built only on demand.
func _get_solution_debug_snapshot() -> Dictionary:
	var reference: Variant = _reference_aircraft_ref.get_ref() \
		if _reference_aircraft_ref != null else null
	var reference_alive := reference != null \
		and is_instance_valid(reference) \
		and (reference as AircraftUnit).is_alive()
	var snapshot := {
		"reference_aircraft_id": _reference_aircraft_instance_id,
		"reference_aircraft_alive": reference_alive,
		"reference_aircraft_position":
			(reference as AircraftUnit).global_position \
			if reference_alive else Vector3.ZERO,
		"reference_aircraft_velocity":
			(reference as AircraftUnit).velocity \
			if reference_alive else Vector3.ZERO,
	}
	if _attack_solution != null:
		snapshot.merge(_attack_solution.to_debug_dictionary())
	return snapshot


#region Target selection policy
func _build_request_for_ship(target_ship: ShipUnit) -> DiveBombTargetRequest:
	var request := DiveBombTargetRequest.new()
	request.source = DiveBombTargetRequest.Source.AI
	request.set_explicit_target(target_ship)
	request.designated_world_position = target_ship.global_position \
		if target_ship != null and is_instance_valid(target_ship) \
		else Vector3.ZERO
	var dive_data := _get_dive_data()
	request.acquisition_radius_m = \
		dive_data.get_target_acquisition_radius_m() \
		if dive_data != null else 0.0
	request.requesting_team = owner_squadron.get_team() \
		if owner_squadron != null else &"neutral"
	# A ship strike exists to sink that ship: when it is gone and no other
	# hostile ship is near, the mission fails safely and returns instead of
	# wasting the sortie on empty water. Position-designated orders (player
	# clicks, AI area strikes) set allow_position_fallback = true instead.
	request.allow_position_fallback = false
	return request


## One resolver run: explicit ship first, then the radius around the
## designation, then the position fallback. Only ever called at command
## receipt, pass start, approach repath ticks and target loss — never per
## physics frame, and once per squadron rather than per aircraft.
func _resolve_target() -> void:
	if _target_request == null:
		return
	_attack_context.target_resolve_count += 1
	_resolved_target = DiveBombTargetResolver.resolve(
		_target_request,
		owner_squadron.get_dive_bomb_candidate_ships()
	)
	var ship := _resolved_target.get_ship()
	_target_ref = weakref(ship) if ship != null else null
	# An explicit ship drags the designation with it, so a later loss searches
	# around where the ship actually was, not where the order started.
	if ship != null and _target_request.get_explicit_target() == ship:
		_target_request.designated_world_position = ship.global_position


func _reacquire_target() -> void:
	_attack_context.target_reacquire_count += 1
	_resolve_target()


## Adapter for legacy callers/tests that assign _target_ref directly instead
## of running setup(): adopts the ship as an explicit AI target. A dead ship
## is deliberately NOT adopted, so the state-specific loss policy applies.
func _adopt_legacy_target_ref() -> void:
	if _target_request != null or _target_ref == null:
		return
	var value: Variant = _target_ref.get_ref()
	if value == null or not is_instance_valid(value):
		return
	var ship := value as ShipUnit
	if ship == null or not ship.is_alive():
		return
	_target_request = _build_request_for_ship(ship)
	_attack_context.squadron_combat_id = owner_squadron.get_instance_id()
	if _attack_context.attack_pass_index <= 0:
		_attack_context.reset_for_new_pass()
	_resolve_target()


## State-based target lock and reacquisition policy. Returns false when the
## current update must stop (state was changed by loss handling).
func _refresh_target_for_state() -> bool:
	if _resolved_target == null or not _resolved_target.is_valid():
		match state:
			State.APPROACHING, State.DIVE_ENTRY:
				_finish_and_return(false)
				return false
			State.DIVING:
				_pull_out_after_target_loss()
				return false
			_:
				return true
	if not _resolved_target.is_ship_target_lost():
		return true
	# The resolved ship is gone.
	match state:
		State.APPROACHING:
			# Search the original designation again; a new hostile ship gets a
			# new solution (and a new deterministic dispersion via its target
			# identity), otherwise the position fallback takes over.
			_reacquire_target()
			if _resolved_target == null or not _resolved_target.is_valid():
				_finish_and_return(false)
				return false
			return true
		State.DIVE_ENTRY:
			# One reacquisition before the dive commits; after that the last
			# known point is attacked as a fixed position.
			if not _dive_entry_reacquire_used:
				_dive_entry_reacquire_used = true
				_reacquire_target()
			else:
				_hold_last_aim_as_position_target()
			if _resolved_target == null or not _resolved_target.is_valid():
				_finish_and_return(false)
				return false
			return true
		State.DIVING:
			var controller := owner_squadron.dive_bomb_controller
			if controller != null and controller.has_attack_solution \
					and controller.is_solution_locked():
				# Committed dive: never swerves to a new ship and never turns
				# away — it keeps the locked intended impact point.
				_hold_last_aim_as_position_target(
					controller.predicted_impact_position
				)
				return true
			_pull_out_after_target_loss()
			return false
		_:
			return true


## Converts a lost ship target into a fixed position target at the last aim
## point, preserving the designation for diagnostics.
func _hold_last_aim_as_position_target(
		aim_override: Vector3 = Vector3.INF
) -> void:
	var held := DiveBombResolvedTarget.new()
	held.type = DiveBombResolvedTarget.TargetType.WORLD_POSITION
	held.designated_world_position = \
		_resolved_target.designated_world_position
	held.resolved_aim_position = aim_override \
		if aim_override.is_finite() \
		else _resolved_target.resolved_aim_position
	held.target_velocity = Vector3.ZERO
	held.resolution_reason = &"target_lost_position_hold"
	_resolved_target = held
	_target_ref = null
#endregion


func _update_approaching(delta: float) -> void:
	_approach_repath_left = maxf(
		_approach_repath_left - maxf(delta, 0.0),
		0.0
	)
	if not _destination_initialized or _approach_repath_left <= 0.0:
		# Repath tick: re-confirm the target (a position order may acquire a
		# ship that sailed into the radius), then re-solve the approach.
		_resolve_target()
		if _resolved_target == null or not _resolved_target.is_valid():
			_finish_and_return(false)
			return
		var next_position := _calculate_approach_position()
		_approach_repath_left = _get_approach_repath_interval()
		if not _destination_initialized \
				or _current_mission_destination.distance_to(next_position) \
					>= _get_approach_repath_threshold():
			_last_approach_position = next_position
			_current_mission_destination = next_position
			_active_destination_serial = \
				owner_squadron.set_mission_destination(next_position)
			_destination_initialized = true
	if not owner_squadron.has_reached_mission_destination(
		_active_destination_serial
	):
		return
	state = State.DIVE_ENTRY
	_destination_initialized = false
	_active_destination_serial = -1


func _update_dive_entry(delta: float) -> void:
	var controller := owner_squadron.dive_bomb_controller
	if controller == null:
		_finish_and_return(false)
		return
	if controller.is_active():
		if owner_squadron.dive_control_source \
				== AircraftSquadron.DiveControlSource.AI:
			state = State.DIVING
			return
		_finish_and_return(false)
		return
	# Repath the entry point while a moving target drags it around. Without
	# this the destination is computed once and goes stale during the transit,
	# which was the measured cause of the ~100-150 m forward miss: the dive
	# then starts from the wrong spot and the locked trajectory cannot fix it.
	_dive_entry_repath_left = maxf(_dive_entry_repath_left - delta, 0.0)
	if not _destination_initialized or _dive_entry_repath_left <= 0.0:
		var navigation_solution := _solve_navigation(false)
		if navigation_solution != null and navigation_solution.valid:
			# Aim the waypoint at the RELEASE point's ground track, not the
			# entry: the formation center is a kinematic phantom the real
			# aircraft chase from ~100+ m behind, so a center-based arrival at
			# the entry fires while the reference aircraft is still short of
			# dive range. Flying through the entry toward the release keeps
			# everyone moving until the reference-distance gate commits the
			# dive at true geometry. The waypoint keeps the ENTRY altitude -
			# the squadron must stay level until the dive itself descends.
			var next_entry := navigation_solution.release_position
			next_entry.y = navigation_solution.dive_entry_position.y
			if not _destination_initialized \
					or _last_dive_entry_position.distance_to(next_entry) \
						>= DIVE_ENTRY_REPATH_THRESHOLD_M:
				_last_dive_entry_position = next_entry
				_active_destination_serial = \
					owner_squadron.set_mission_destination(next_entry, true)
				_destination_initialized = true
		elif not _destination_initialized:
			_last_dive_entry_position = _calculate_dive_entry_position()
			_active_destination_serial = \
				owner_squadron.set_mission_destination(
					_last_dive_entry_position,
					true
				)
			_destination_initialized = true
		_dive_entry_repath_left = DIVE_ENTRY_REPATH_INTERVAL_SEC
	# Commit the dive on geometry, not on waypoint arrival: start exactly when
	# the horizontal distance to the intended impact matches the fixed
	# trajectory's total horizontal travel. Waypoint arrival stays as a
	# fallback for solver failures.
	if not _try_begin_dive_on_distance_gate(controller):
		if not owner_squadron.has_reached_mission_destination(
			_active_destination_serial
		):
			return
		if _gate_probe_valid \
				and _gate_distance_m > _gate_required_travel_m \
					+ DIVE_COMMIT_MARGIN_M:
			# Waypoint reached, but the REFERENCE aircraft (which trails the
			# kinematic formation center) is still short of dive range. On the
			# fixed dive path the predicted impact barely moves, so beginning
			# now would leave a forward error the release window can never
			# recover. Push the waypoint through the aim point and keep
			# closing until the distance gate commits at true geometry.
			var push_destination := _gate_final_aim \
				+ _gate_attack_direction * DIVE_ENTRY_PUSH_THROUGH_M
			push_destination.y = _last_dive_entry_position.y
			_last_dive_entry_position = push_destination
			_active_destination_serial = \
				owner_squadron.set_mission_destination(push_destination, true)
			_destination_initialized = true
			return
		_begin_dive_from_entry(controller)


## Distance-gated dive commit: begins the dive the moment the reference
## aircraft's horizontal distance to the intended impact point equals the
## fixed trajectory's total horizontal travel (dive + bomb), so the release
## window's impact sweep crosses the target near its center.
func _try_begin_dive_on_distance_gate(
		controller: DiveBombAttackController
) -> bool:
	_gate_probe_valid = false
	var reference := _get_reference_aircraft()
	if reference == null:
		return false
	var gate_solution := _solve_commit()
	if gate_solution == null or not gate_solution.valid:
		return false
	var gate := DiveBombAttackPlanner.evaluate_commit_gate(
		reference.global_position,
		gate_solution,
		DIVE_COMMIT_MARGIN_M
	)
	_gate_probe_valid = true
	_gate_distance_m = gate["distance_m"]
	_gate_required_travel_m = gate["required_travel_m"]
	_gate_final_aim = gate["final_aim"]
	_gate_attack_direction = gate["attack_direction"]
	if not gate["should_commit"]:
		return false
	var begin_result := controller.begin_dive_with_solution(
		gate_solution,
		AircraftSquadron.DiveControlSource.AI,
		0.0,
		reference
	)
	match begin_result:
		DiveBombAttackController.BeginDiveResult.STARTED, \
				DiveBombAttackController.BeginDiveResult \
					.ALREADY_ACTIVE_SAME_SOURCE:
			state = State.DIVING
			return true
	return false


func _begin_dive_from_entry(
		controller: DiveBombAttackController
) -> void:
	# One solution drives everything: impact, release, entry, direction. The
	# snapshot is applied inside begin_dive_with_solution after its internal
	# reset, so a second attack pass cannot lose the planned positions.
	# Anchor on the reference aircraft's REAL position: the prescriptive
	# solve's carrier->target axis ignores the reference's lateral formation
	# offset, which becomes a full-width lateral miss on the parallel dive.
	var reference := _get_reference_aircraft()
	var entry_solution := _solve_commit() \
		if reference != null else _solve_navigation(false)
	var begin_result: DiveBombAttackController.BeginDiveResult
	if entry_solution != null and entry_solution.valid:
		begin_result = controller.begin_dive_with_solution(
			entry_solution,
			AircraftSquadron.DiveControlSource.AI,
			0.0,
			reference
		)
	else:
		# Solver failure: keep the legacy point-based dive as a safe fallback.
		begin_result = controller.begin_dive_with_source(
			_calculate_predicted_target_position(),
			_resolved_target.get_target_velocity(),
			AircraftSquadron.DiveControlSource.AI
		)
	match begin_result:
		DiveBombAttackController.BeginDiveResult.STARTED, \
				DiveBombAttackController.BeginDiveResult \
					.ALREADY_ACTIVE_SAME_SOURCE:
			state = State.DIVING
		DiveBombAttackController.BeginDiveResult.NO_AMMUNITION, \
				DiveBombAttackController.BeginDiveResult \
					.INVALID_CONFIGURATION, \
				DiveBombAttackController.BeginDiveResult \
					.CONTROL_CONFLICT, \
				DiveBombAttackController.BeginDiveResult \
					.RELEASE_CONFLICT:
			_finish_and_return(false)


func _update_diving() -> void:
	var controller := owner_squadron.dive_bomb_controller
	if controller == null:
		_finish_and_return(false)
		return
	if not controller.is_solution_locked():
		# Final refresh, then lock. The solve is re-anchored to the reference
		# aircraft's ACTUAL position: whatever entry error the approach left
		# becomes honest miss distance on a flyable trajectory, instead of a
		# release point the fixed-direction dive can never reach.
		var final_solution := _solve_commit(
			controller.locked_attack_direction \
			if controller.has_attack_solution else Vector3.ZERO
		)
		if final_solution != null and final_solution.valid:
			controller.update_attack_solution(final_solution)
		else:
			controller.update_target(
				_calculate_predicted_target_position(),
				_resolved_target.get_target_velocity()
			)
		if owner_squadron.dive_control_source \
				== AircraftSquadron.DiveControlSource.AI:
			controller.lock_solution()
	match controller.state:
		DiveBombAttackController.State.DIVE_ENTRY, \
				DiveBombAttackController.State.DIVING, \
				DiveBombAttackController.State.RELEASING:
			return
		DiveBombAttackController.State.PULLING_OUT:
			state = State.PULLING_OUT
		DiveBombAttackController.State.COMPLETED:
			if controller.get_attack_result_data().released_count > 0:
				_begin_egress()
			else:
				_finish_and_return(false)
		DiveBombAttackController.State.FAILED:
			_finish_and_return(false)
		_:
			pass


func _pull_out_after_target_loss() -> void:
	var controller := owner_squadron.dive_bomb_controller
	if controller == null:
		_finish_and_return(false)
		return
	match controller.state:
		DiveBombAttackController.State.DIVE_ENTRY, \
				DiveBombAttackController.State.DIVING, \
				DiveBombAttackController.State.RELEASING:
			# Pending payload stays on the aircraft. Requests that already created
			# projectiles remain independent and are never deleted by pull-out.
			controller.begin_pull_out()
			state = State.PULLING_OUT
		DiveBombAttackController.State.PULLING_OUT:
			state = State.PULLING_OUT
		DiveBombAttackController.State.COMPLETED, \
				DiveBombAttackController.State.FAILED:
			_finish_and_return(false)
		_:
			_finish_and_return(false)


func _update_pulling_out() -> void:
	var controller := owner_squadron.dive_bomb_controller
	if controller == null \
			or controller.state == DiveBombAttackController.State.FAILED:
		_finish_and_return(false)
		return
	if controller.state != DiveBombAttackController.State.COMPLETED:
		return
	if controller.get_attack_result_data().released_count <= 0:
		_finish_and_return(false)
		return
	_begin_egress()


func _begin_egress() -> void:
	var direction := owner_squadron.get_formation_forward()
	direction.y = 0.0
	if direction.length_squared() <= EPSILON and _resolved_target != null \
			and _resolved_target.is_valid():
		direction = _resolved_target.get_aim_position() \
			- owner_squadron.formation_center
		direction.y = 0.0
	direction = direction.normalized() \
		if direction.length_squared() > EPSILON else Vector3.FORWARD
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	var distance := weapon_data.attack_egress_distance_m \
		if weapon_data != null else 700.0
	var destination := owner_squadron.formation_center \
		+ direction * maxf(distance, 0.0)
	destination.y = _get_operating_world_altitude()
	_active_destination_serial = owner_squadron.set_mission_destination(
		destination,
		true
	)
	state = State.EGRESS


func _update_egress() -> void:
	if not owner_squadron.has_reached_mission_destination(
		_active_destination_serial
	):
		return
	successful = true
	_finished = true
	state = State.COMPLETED
	_target_ref = null
	if mission_data == null or mission_data.return_after_attack:
		state = State.RETURNING
		owner_squadron.request_return()


func _finish_and_return(was_successful: bool) -> void:
	if _finished:
		return
	_cancel_dive()
	successful = was_successful
	_finished = true
	state = State.COMPLETED if was_successful else State.FAILED
	_target_ref = null
	if owner_squadron != null and is_instance_valid(owner_squadron):
		state = State.RETURNING
		owner_squadron.request_return()


func _cancel_dive() -> void:
	if owner_squadron != null \
			and is_instance_valid(owner_squadron) \
			and owner_squadron.dive_bomb_controller != null:
		owner_squadron.dive_bomb_controller.cancel()
		owner_squadron.dive_control_source = \
			AircraftSquadron.DiveControlSource.NONE


#region Planning delegation
## Navigation-phase solve toward the resolved target; the planner assembles
## every resolver input. Keeps the latest valid geometry for diagnostics.
func _solve_navigation(
		include_approach_time: bool
) -> DiveBombAttackSolution:
	var solution := DiveBombAttackPlanner.build_navigation_solution(
		owner_squadron,
		_get_reference_aircraft(),
		_resolved_target,
		_get_dive_data(),
		_get_bomb_weapon_data(),
		include_approach_time,
		_attack_context
	)
	if solution != null and solution.valid:
		_attack_solution = solution
	return solution


## Commit/lock solve anchored on the reference aircraft's real position, with
## the pass's deterministic accuracy dispersion applied by the planner.
func _solve_commit(
		locked_direction: Vector3 = Vector3.ZERO
) -> DiveBombAttackSolution:
	var reference := _get_reference_aircraft()
	if reference == null:
		return null
	var solution := DiveBombAttackPlanner.build_commit_solution(
		owner_squadron,
		reference,
		_resolved_target,
		_get_dive_data(),
		_get_bomb_weapon_data(),
		_attack_context,
		locked_direction
	)
	if solution != null and solution.valid:
		_attack_solution = solution
	return solution


## Approach point of the current attack solution. Falls back to the previous
## straight-line geometry only when the solver fails, so a failure still leaves
## the squadron somewhere sane.
func _calculate_approach_position() -> Vector3:
	var solution := _solve_navigation(true)
	if solution != null and solution.valid:
		return solution.approach_position
	var aim := _resolved_target.get_aim_position()
	var direction := DiveBombAttackPlanner.get_attack_direction(
		owner_squadron,
		aim
	)
	var dive_data := _get_dive_data()
	var result := aim - direction * maxf(dive_data.approach_distance_m, 0.0)
	result.y = aim.y + maxf(dive_data.dive_entry_altitude_m, 1.0)
	return result


## Dive entry of the current attack solution: far enough behind the release
## point to cover the aircraft's horizontal travel during the dive.
func _calculate_dive_entry_position() -> Vector3:
	var solution := _solve_navigation(true)
	if solution != null and solution.valid:
		return solution.dive_entry_position
	var dive_data := _get_dive_data()
	var height := maxf(dive_data.dive_entry_altitude_m, 1.0)
	var tangent := tan(deg_to_rad(clampf(
		dive_data.dive_angle_degrees,
		1.0,
		89.0
	)))
	var horizontal_distance := (
		dive_data.dive_entry_horizontal_distance_m
		if dive_data.dive_entry_horizontal_distance_m > 0.0 \
		else height / maxf(tangent, 0.01)
	)
	var predicted := _calculate_predicted_target_position()
	var aim := _resolved_target.get_aim_position()
	var result := predicted - DiveBombAttackPlanner.get_attack_direction(
		owner_squadron,
		aim
	) * horizontal_distance
	result.y = aim.y + height
	return result


## Impact point the bomb should reach. Prefers the full attack solution, which
## accounts for dive time, release delay and bomb fall time; the old
## fall-time-only estimate remains as a fallback.
func _calculate_predicted_target_position() -> Vector3:
	var aim := _resolved_target.get_aim_position()
	if mission_data == null or not mission_data.target_prediction_enabled:
		return aim
	if _attack_solution != null and _attack_solution.valid:
		return _attack_solution.predicted_impact_position
	var height := maxf(owner_squadron.formation_center.y - aim.y, 1.0)
	var gravity := DiveBombAttackPlanner.get_world_gravity()
	var fall_time := sqrt(2.0 * height / maxf(gravity, 0.1))
	return aim + _resolved_target.get_target_velocity() * fall_time
#endregion


func _get_approach_repath_interval() -> float:
	return maxf(
		mission_data.approach_repath_interval_sec \
		if mission_data != null else 0.5,
		0.0
	)


func _get_approach_repath_threshold() -> float:
	return maxf(
		mission_data.approach_repath_threshold_m \
		if mission_data != null else 150.0,
		0.0
	)


func _get_bomb_weapon_data() -> AircraftWeaponData:
	var data := owner_squadron.squadron_data.aircraft_data \
		if owner_squadron != null \
		and owner_squadron.squadron_data != null else null
	return data.weapon_data if data != null else null


func _get_operating_world_altitude() -> float:
	var carrier := owner_squadron.get_owner_carrier()
	var base_height := carrier.global_position.y if carrier != null else 0.0
	return base_height \
		+ owner_squadron.squadron_data.aircraft_data.operating_altitude_m


func _get_dive_data() -> DiveBomberCombatData:
	return owner_squadron.squadron_data.aircraft_data \
		.dive_bomber_combat_data


func _get_target_ship() -> Node3D:
	if _resolved_target != null:
		return _resolved_target.get_ship()
	if _target_ref == null:
		return null
	var target := _target_ref.get_ref() as Node3D
	if target == null or not is_instance_valid(target) \
			or target.is_queued_for_deletion():
		return null
	if target.has_method(&"is_alive") and not bool(target.call(&"is_alive")):
		return null
	return target


func _is_valid_squadron_setup() -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.DIVE_BOMBER \
		and owner_squadron.dive_bomb_controller != null \
		and _get_dive_data() != null \
		and _get_dive_data().validate().is_empty() \
		and mission_data != null \
		and mission_data.validate().is_empty() \
		and mission_data.mission_type \
			== AirMissionData.MissionType.STRIKE_SHIP


func _is_valid_setup(target: Node3D) -> bool:
	return _is_valid_squadron_setup() \
		and target != null \
		and is_instance_valid(target) \
		and target is ShipUnit
