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
			_update_dive_entry(target)
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


func _update_dive_entry(target: Node3D) -> void:
	if not _destination_initialized:
		_last_dive_entry_position = _calculate_dive_entry_position(target)
		_active_destination_serial = \
			owner_squadron.set_mission_destination(
				_last_dive_entry_position,
				true
			)
		_destination_initialized = true
	if not owner_squadron.has_reached_mission_destination(
		_active_destination_serial
	):
		return
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
	# One solution drives everything: impact, release, entry, direction. The
	# snapshot is applied inside begin_dive_with_solution after its internal
	# reset, so a second attack pass cannot lose the planned positions.
	var entry_solution := _solve_attack(target, false)
	var begin_result: DiveBombAttackController.BeginDiveResult
	if entry_solution != null and entry_solution.valid:
		begin_result = controller.begin_dive_with_solution(
			entry_solution,
			AircraftSquadron.DiveControlSource.AI
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
	if target == null or not is_instance_valid(target):
		return null
	var dive_data := _get_dive_data()
	var weapon_data := _get_bomb_weapon_data()
	if dive_data == null or weapon_data == null:
		return null
	var reference := _get_reference_aircraft()
	if reference == null:
		return null
	var attack_direction := controller.locked_attack_direction \
		if controller.has_attack_solution else _get_attack_direction(target)
	var solution := DiveBombAttackResolver.solve_from_current_dive_state(
		reference.global_position,
		target.global_position,
		_get_target_velocity(target),
		target.global_position.y,
		dive_data,
		weapon_data,
		_get_world_gravity(),
		attack_direction
	)
	if solution != null and solution.valid:
		_solution_revision += 1
		solution.revision = _solution_revision
		_attack_solution = solution
	return solution


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
