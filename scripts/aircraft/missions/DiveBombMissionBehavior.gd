extends RefCounted
class_name DiveBombMissionBehavior

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
var _solution_revision := 0
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

## Deterministic per-pass accuracy offset (XZ). Zero at full accuracy; the
## solver aims at exact + offset so a low-skill crew misses precisely where
## the roll says, with untouched ballistics.
var _pass_dispersion_offset := Vector3.ZERO
var _attack_pass_index := 0
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
	_target_ref = weakref(target_ship)
	state = State.APPROACHING
	successful = false
	_finished = false
	# One deterministic accuracy roll per attack pass (§36): the offset stays
	# constant through every re-solve of this pass.
	_roll_pass_dispersion_offset(target_ship)
	_destination_initialized = false
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
	var target := _get_target_ship()
	if target == null and state in [State.APPROACHING, State.DIVE_ENTRY]:
		_finish_and_return(false)
		return
	if target == null and state == State.DIVING:
		_pull_out_after_target_loss()
		return
	match state:
		State.APPROACHING:
			_update_approaching(target, delta)
		State.DIVE_ENTRY:
			_update_dive_entry(target, delta)
		State.DIVING:
			_update_diving(target)
		State.PULLING_OUT:
			_update_pulling_out(target)
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


func get_state() -> int:
	return int(state)


func is_finished() -> bool:
	return _finished


func get_target_ship() -> Node3D:
	return _get_target_ship()


func get_debug_snapshot() -> Dictionary:
	var controller_state := "MISSING"
	var controller_result := {}
	if owner_squadron != null and is_instance_valid(owner_squadron) \
			and owner_squadron.dive_bomb_controller != null:
		var controller := owner_squadron.dive_bomb_controller
		controller_state = DiveBombAttackController.State.keys()[
			int(controller.state)
		]
		controller_result = controller.get_attack_result_data().to_dictionary()
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
	}.merged(_get_solution_debug_snapshot())


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


func _update_approaching(target: Node3D, delta: float) -> void:
	_approach_repath_left = maxf(
		_approach_repath_left - maxf(delta, 0.0),
		0.0
	)
	var next_position := _calculate_approach_position(target)
	var should_update := not _destination_initialized \
		or (
			_approach_repath_left <= 0.0
			and _current_mission_destination.distance_to(next_position) \
				>= _get_approach_repath_threshold()
		)
	if should_update:
		_last_approach_position = next_position
		_current_mission_destination = next_position
		_active_destination_serial = \
			owner_squadron.set_mission_destination(next_position)
		_destination_initialized = true
		_approach_repath_left = _get_approach_repath_interval()
	if not owner_squadron.has_reached_mission_destination(
		_active_destination_serial
	):
		return
	state = State.DIVE_ENTRY
	_destination_initialized = false
	_active_destination_serial = -1


func _update_dive_entry(target: Node3D, delta: float) -> void:
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
		var navigation_solution := _solve_attack(target, false)
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
			_last_dive_entry_position = _calculate_dive_entry_position(target)
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
	if not _try_begin_dive_on_distance_gate(target, controller):
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
		_begin_dive_from_entry(target, controller)


## Distance-gated dive commit: begins the dive the moment the reference
## aircraft's horizontal distance to the intended impact point equals the
## fixed trajectory's total horizontal travel (dive + bomb), so the release
## window's impact sweep crosses the target near its center.
func _try_begin_dive_on_distance_gate(
		target: Node3D,
		controller: DiveBombAttackController
) -> bool:
	_gate_probe_valid = false
	var reference := _get_reference_aircraft()
	if reference == null:
		return false
	var gate_solution := _solve_current_state(target, reference)
	if gate_solution == null or not gate_solution.valid:
		return false
	var required_travel := gate_solution.horizontal_dive_distance_m \
		+ gate_solution.bomb_horizontal_travel_m
	var to_intended := gate_solution.intended_target_impact_position \
		- reference.global_position
	to_intended.y = 0.0
	_gate_probe_valid = true
	_gate_distance_m = to_intended.length()
	_gate_required_travel_m = required_travel
	_gate_final_aim = gate_solution.final_aim_impact_position
	_gate_attack_direction = gate_solution.attack_direction
	if to_intended.length() > required_travel + DIVE_COMMIT_MARGIN_M:
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
		target: Node3D,
		controller: DiveBombAttackController
) -> void:
	# One solution drives everything: impact, release, entry, direction. The
	# snapshot is applied inside begin_dive_with_solution after its internal
	# reset, so a second attack pass cannot lose the planned positions.
	# Anchor on the reference aircraft's REAL position: the prescriptive
	# solve's carrier->target axis ignores the reference's lateral formation
	# offset, which becomes a full-width lateral miss on the parallel dive.
	var reference := _get_reference_aircraft()
	var entry_solution := _solve_current_state(target, reference) \
		if reference != null else _solve_attack(target, false)
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
			_calculate_predicted_target_position(target),
			_get_target_velocity(target),
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


func _update_diving(target: Node3D) -> void:
	var controller := owner_squadron.dive_bomb_controller
	if controller == null:
		_finish_and_return(false)
		return
	if target != null and not controller.is_solution_locked():
		# Final refresh, then lock. The solve is re-anchored to the reference
		# aircraft's ACTUAL position: whatever entry error the approach left
		# becomes honest miss distance on a flyable trajectory, instead of a
		# release point the fixed-direction dive can never reach.
		var final_solution := _solve_locked_dive_state(target, controller)
		if final_solution != null and final_solution.valid:
			controller.update_attack_solution(final_solution)
		else:
			controller.update_target(
				_calculate_predicted_target_position(target),
				_get_target_velocity(target)
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
				_begin_egress(target)
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


func _update_pulling_out(target: Node3D) -> void:
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
	_begin_egress(target)


func _begin_egress(target: Node3D) -> void:
	var direction := owner_squadron.get_formation_forward()
	direction.y = 0.0
	if direction.length_squared() <= EPSILON and target != null:
		direction = target.global_position - owner_squadron.formation_center
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


## Approach point of the current attack solution. Falls back to the previous
## straight-line geometry only when the solver fails, so a failure still leaves
## the squadron somewhere sane.
func _calculate_approach_position(target: Node3D) -> Vector3:
	var solution := _solve_attack(target, true)
	if solution != null and solution.valid:
		return solution.approach_position
	var direction := _get_attack_direction(target)
	var dive_data := _get_dive_data()
	var result := target.global_position \
		- direction * maxf(dive_data.approach_distance_m, 0.0)
	result.y = target.global_position.y \
		+ maxf(dive_data.dive_entry_altitude_m, 1.0)
	return result


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


## Dive entry of the current attack solution: far enough behind the release
## point to cover the aircraft's horizontal travel during the dive.
func _calculate_dive_entry_position(target: Node3D) -> Vector3:
	var solution := _solve_attack(target, true)
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
	var predicted := _calculate_predicted_target_position(target)
	var result := predicted \
		- _get_attack_direction(target) * horizontal_distance
	result.y = target.global_position.y + height
	return result


## Solves the attack backwards from the bomb impact point.
##
## Cheap pure-vector math, but still only called from the repath paths rather
## than every physics frame. `include_approach_time` is false once the squadron
## is at its dive entry, because the approach leg no longer delays the bomb.
func _solve_attack(
		target: Node3D,
		include_approach_time: bool
) -> DiveBombAttackSolution:
	if target == null or not is_instance_valid(target):
		return null
	var dive_data := _get_dive_data()
	var weapon_data := _get_bomb_weapon_data()
	if dive_data == null or weapon_data == null:
		return null
	# One solve per squadron, anchored on the central reference aircraft.
	# Individual aircraft never run their own resolver.
	var reference := _get_reference_aircraft()
	var solve_position := reference.global_position \
		if reference != null else owner_squadron.formation_center
	var solve_forward := -reference.global_transform.basis.z \
		if reference != null else owner_squadron.get_formation_forward()
	var solution := DiveBombAttackResolver.solve(
		solve_position,
		solve_forward,
		_get_formation_speed_mps(),
		target.global_position,
		_get_target_velocity(target),
		target.global_position.y,
		dive_data,
		weapon_data,
		_get_world_gravity(),
		_get_attack_direction(target),
		include_approach_time
	)
	if solution != null and solution.valid:
		_solution_revision += 1
		solution.revision = _solution_revision
		_attack_solution = solution
	return solution


## The lock-time solve: forward-projects the already-committed attack
## direction from the reference aircraft's real position.
func _solve_locked_dive_state(
		target: Node3D,
		controller: DiveBombAttackController
) -> DiveBombAttackSolution:
	var reference := _get_reference_aircraft()
	if reference == null:
		return null
	var locked_direction := controller.locked_attack_direction \
		if controller.has_attack_solution else Vector3.ZERO
	return _solve_current_state(target, reference, locked_direction)


## Current-state solve shared by the dive commit gate and the lock
## refresh. Aims at the intended point (plus the pass's deterministic
## accuracy offset) unless a committed dive supplies its locked heading.
func _solve_current_state(
		target: Node3D,
		reference: AircraftUnit,
		locked_direction: Vector3 = Vector3.ZERO
) -> DiveBombAttackSolution:
	if target == null or not is_instance_valid(target):
		return null
	var dive_data := _get_dive_data()
	var weapon_data := _get_bomb_weapon_data()
	if dive_data == null or weapon_data == null:
		return null
	var solution := DiveBombAttackResolver.solve_from_current_dive_state(
		reference.global_position,
		target.global_position,
		_get_target_velocity(target),
		target.global_position.y,
		dive_data,
		weapon_data,
		_get_world_gravity(),
		locked_direction,
		_pass_dispersion_offset
	)
	if solution != null and solution.valid:
		solution.base_accuracy = dive_data.base_bombing_accuracy
		solution.final_accuracy = dive_data.base_bombing_accuracy
		solution.dispersion_radius_m = _pass_dispersion_offset.length()
		_solution_revision += 1
		solution.revision = _solution_revision
		_attack_solution = solution
	return solution


## Deterministic per-pass accuracy roll (never global randf, never time
## or frame based). Radius shrinks linearly with accuracy; direction and
## magnitude come from one seeded RNG so identical setups reproduce.
func _roll_pass_dispersion_offset(target: Node3D) -> void:
	_attack_pass_index += 1
	_pass_dispersion_offset = Vector3.ZERO
	var dive_data := _get_dive_data()
	if dive_data == null or target == null \
			or not is_instance_valid(target):
		return
	_pass_dispersion_offset = \
		DiveBombAttackResolver.resolve_accuracy_dispersion_offset(
			dive_data.base_bombing_accuracy,
			dive_data.accuracy_minimum_dispersion_radius_m,
			dive_data.accuracy_maximum_dispersion_radius_m,
			hash([
				owner_squadron.get_instance_id(),
				target.get_instance_id(),
				_attack_pass_index,
				_solution_revision,
			])
		)
func _get_bomb_weapon_data() -> AircraftWeaponData:
	var data := owner_squadron.squadron_data.aircraft_data 		if owner_squadron != null 		and owner_squadron.squadron_data != null else null
	return data.weapon_data if data != null else null


func _get_formation_speed_mps() -> float:
	var velocity := owner_squadron.get_formation_velocity() 		if owner_squadron.has_method(&"get_formation_velocity") else Vector3.ZERO
	var speed := velocity.length()
	if speed > 0.1:
		return speed
	var data := owner_squadron.squadron_data.aircraft_data 		if owner_squadron != null 		and owner_squadron.squadron_data != null else null
	return maxf(data.cruise_speed_mps, 1.0) if data != null else 1.0


func _get_world_gravity() -> float:
	return float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))


## Impact point the bomb should reach. Prefers the full attack solution, which
## accounts for dive time, release delay and bomb fall time; the old
## fall-time-only estimate remains as a fallback.
func _calculate_predicted_target_position(target: Node3D) -> Vector3:
	if mission_data == null or not mission_data.target_prediction_enabled:
		return target.global_position
	if _attack_solution != null and _attack_solution.valid:
		return _attack_solution.predicted_impact_position
	var height := maxf(
		owner_squadron.formation_center.y - target.global_position.y,
		1.0
	)
	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var fall_time := sqrt(2.0 * height / maxf(gravity, 0.1))
	return target.global_position + _get_target_velocity(target) * fall_time


func _get_attack_direction(target: Node3D) -> Vector3:
	var carrier := owner_squadron.get_owner_carrier()
	var origin := carrier.global_position \
		if carrier != null else owner_squadron.formation_center
	var direction := target.global_position - origin
	direction.y = 0.0
	return direction.normalized() \
		if direction.length_squared() > EPSILON else Vector3.FORWARD


func _get_target_velocity(target: Node3D) -> Vector3:
	if target.has_method(&"get_world_velocity"):
		var world_velocity: Variant = target.call(&"get_world_velocity")
		if world_velocity is Vector3:
			return world_velocity
	var body := target as CharacterBody3D
	if body != null:
		return body.velocity
	var value: Variant = target.get(&"velocity")
	return value as Vector3 if value is Vector3 else Vector3.ZERO


func _get_operating_world_altitude() -> float:
	var carrier := owner_squadron.get_owner_carrier()
	var base_height := carrier.global_position.y if carrier != null else 0.0
	return base_height \
		+ owner_squadron.squadron_data.aircraft_data.operating_altitude_m


func _get_dive_data() -> DiveBomberCombatData:
	return owner_squadron.squadron_data.aircraft_data \
		.dive_bomber_combat_data


func _get_target_ship() -> Node3D:
	if _target_ref == null:
		return null
	var target := _target_ref.get_ref() as Node3D
	if target == null or not is_instance_valid(target) \
			or target.is_queued_for_deletion():
		return null
	if target.has_method(&"is_alive") and not bool(target.call(&"is_alive")):
		return null
	return target


func _is_valid_setup(target: Node3D) -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.DIVE_BOMBER \
		and owner_squadron.dive_bomb_controller != null \
		and _get_dive_data() != null \
		and _get_dive_data().validate().is_empty() \
		and target != null \
		and is_instance_valid(target) \
		and mission_data != null \
		and mission_data.validate().is_empty() \
		and mission_data.mission_type \
			== AirMissionData.MissionType.STRIKE_SHIP
