extends Node
class_name DiveBombAttackController

signal aircraft_automatic_release_completed(
	aircraft_id: int,
	released_count: int,
	total_aircraft_count: int
)
signal aircraft_automatic_release_failed(aircraft_id: int, reason: int)
signal automatic_release_pass_completed(
	released_count: int,
	failed_count: int,
	skipped_count: int,
	cancelled: bool
)

enum State {
	IDLE,
	DIVE_ENTRY,
	DIVING,
	RELEASING,
	PULLING_OUT,
	COMPLETED,
	FAILED,
}

enum AircraftReleaseState {
	PENDING,
	REQUESTED,
	RELEASED,
	FAILED,
	SKIPPED,
}

enum BeginDiveResult {
	STARTED,
	ALREADY_ACTIVE_SAME_SOURCE,
	INVALID_CONFIGURATION,
	NO_AMMUNITION,
	CONTROL_CONFLICT,
	RELEASE_CONFLICT,
}

enum ReleaseBlockReason {
	NONE,
	TOO_EARLY,
	NO_AMMUNITION,
	WEAPON_DISABLED,
	RELEASE_SEQUENCE_IN_PROGRESS,
	NO_RELEASE_CAPABLE_AIRCRAFT,
	SAFETY_ALTITUDE_REACHED,
	CANCELLED,
	RELEASE_POSITION_MISSED,
	HEADING_NOT_ALIGNED,
	IMPACT_SOLUTION_INVALID,
	REFERENCE_AIRCRAFT_LOST,
}

const EPSILON := 0.0001

var owner_squadron: AircraftSquadron
var dive_data: DiveBomberCombatData
var payload_release_settings: AircraftPayloadReleaseSettings
var release_policy := DiveReleasePolicy.new()
var state: State = State.IDLE
## Where the bomb should land. Kept distinct from the point the aircraft
## actually flies to during the dive.
var target_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
## Where the aircraft must let the bomb go. Solved backwards from
## target_position by DiveBombAttackResolver; falls back to the impact point
## when a caller supplies no solution (player manual dives).
var planned_release_position := Vector3.ZERO
var has_planned_release_position := false
## One central attack solution per squadron. When present, the dive flies a
## locked direction and the release window is judged from the reference
## aircraft; the legacy per-aircraft altitude policy remains for solutionless
## dives (player manual runs).
var attack_solution: DiveBombAttackSolution
var has_attack_solution := false
var predicted_impact_position := Vector3.ZERO
var planned_dive_entry_position := Vector3.ZERO
var locked_attack_direction := Vector3.FORWARD
var locked_dive_direction := Vector3.ZERO
var _reference_aircraft_ref: WeakRef
var _reference_aircraft_instance_id := 0
var solution_locked := false
var dive_elapsed_seconds := 0.0
var release_block_reason: ReleaseBlockReason = ReleaseBlockReason.NONE
var dispersion_radius_m := 0.0
var _rng := RandomNumberGenerator.new()
var _rng_seed_overridden := false

var _pull_out_forward := Vector3.FORWARD
var _aircraft_release_states: Dictionary = {}
var _aircraft_release_attempts: Dictionary = {}
var _aircraft_release_retry_left: Dictionary = {}
var _previous_aircraft_altitudes: Dictionary = {}
var _aircraft_scatter_offsets: Dictionary = {}
var _released_aircraft_count := 0
var _failed_aircraft_count := 0
var _pending_aircraft_count := 0
var _requested_aircraft_count := 0
var _total_release_request_count := 0
var _skipped_aircraft_count := 0
var _release_completion_wait_left := 0.0
var _release_pass_finished := false
var _release_pass_cancelled := false
var _release_conflict_warning_emitted := false


func setup(squadron: AircraftSquadron) -> void:
	shutdown()
	owner_squadron = squadron
	dive_data = squadron.squadron_data.aircraft_data \
		.dive_bomber_combat_data \
		if squadron != null \
		and squadron.squadron_data != null \
		and squadron.squadron_data.aircraft_data != null else null
	payload_release_settings = squadron.squadron_data \
		.payload_release_settings \
		if squadron != null and squadron.squadron_data != null else null
	if owner_squadron != null \
			and not owner_squadron.aircraft_weapon_release_finished \
				.is_connected(_on_aircraft_weapon_release_finished):
		owner_squadron.aircraft_weapon_release_finished.connect(
			_on_aircraft_weapon_release_finished
		)
	reset()


func shutdown() -> void:
	if owner_squadron != null \
			and is_instance_valid(owner_squadron) \
			and owner_squadron.aircraft_weapon_release_finished.is_connected(
				_on_aircraft_weapon_release_finished
			):
		owner_squadron.aircraft_weapon_release_finished.disconnect(
			_on_aircraft_weapon_release_finished
		)
	if owner_squadron != null and is_instance_valid(owner_squadron) \
			and state != State.IDLE:
		cancel()
	reset()
	owner_squadron = null
	dive_data = null
	payload_release_settings = null


func reset() -> void:
	state = State.IDLE
	target_position = Vector3.ZERO
	target_velocity = Vector3.ZERO
	planned_release_position = Vector3.ZERO
	has_planned_release_position = false
	attack_solution = null
	has_attack_solution = false
	predicted_impact_position = Vector3.ZERO
	planned_dive_entry_position = Vector3.ZERO
	locked_attack_direction = Vector3.FORWARD
	locked_dive_direction = Vector3.ZERO
	_reference_aircraft_ref = null
	_reference_aircraft_instance_id = 0
	dive_elapsed_seconds = 0.0
	release_block_reason = ReleaseBlockReason.NONE
	solution_locked = false
	dispersion_radius_m = 0.0
	_pull_out_forward = Vector3.FORWARD
	_aircraft_release_states.clear()
	_aircraft_release_attempts.clear()
	_aircraft_release_retry_left.clear()
	_previous_aircraft_altitudes.clear()
	_aircraft_scatter_offsets.clear()
	_released_aircraft_count = 0
	_failed_aircraft_count = 0
	_pending_aircraft_count = 0
	_requested_aircraft_count = 0
	_total_release_request_count = 0
	_skipped_aircraft_count = 0
	_release_completion_wait_left = 0.0
	_release_pass_finished = false
	_release_pass_cancelled = false
	_release_conflict_warning_emitted = false


func begin_dive_with_source(
		next_target_position: Vector3,
		next_target_velocity: Vector3,
		source: AircraftSquadron.DiveControlSource,
		next_dispersion_radius_m: float = 0.0
) -> BeginDiveResult:
	if source == AircraftSquadron.DiveControlSource.NONE:
		return BeginDiveResult.INVALID_CONFIGURATION
	if is_active():
		return (
			BeginDiveResult.ALREADY_ACTIVE_SAME_SOURCE
			if owner_squadron != null \
			and owner_squadron.dive_control_source == source
			else BeginDiveResult.CONTROL_CONFLICT
		)
	if not _is_valid_dive_squadron():
		return BeginDiveResult.INVALID_CONFIGURATION
	if owner_squadron.dive_control_source \
			not in [AircraftSquadron.DiveControlSource.NONE, source]:
		return BeginDiveResult.CONTROL_CONFLICT
	if owner_squadron.is_weapon_release_in_progress():
		if not _release_conflict_warning_emitted:
			_release_conflict_warning_emitted = true
			push_warning(
				"Cannot begin dive attack while an aircraft payload "
				+ "release is still active."
			)
		return BeginDiveResult.RELEASE_CONFLICT
	if not owner_squadron.has_any_ammunition():
		return BeginDiveResult.NO_AMMUNITION
	if state in [State.COMPLETED, State.FAILED]:
		reset()
	target_position = next_target_position
	target_velocity = next_target_velocity
	# AI keeps tracking while the mission is still reaching DIVE_ENTRY. The
	# solution is frozen only when this controller actually commits to DIVING.
	solution_locked = false
	dispersion_radius_m = maxf(next_dispersion_radius_m, 0.0)
	if not _rng_seed_overridden:
		_rng.seed = hash([
			owner_squadron.get_instance_id() \
				if owner_squadron != null else 0,
			int(target_position.x * 10.0),
			int(target_position.z * 10.0),
		])
	dive_elapsed_seconds = 0.0
	release_block_reason = ReleaseBlockReason.TOO_EARLY
	owner_squadron.dive_control_source = source
	owner_squadron.begin_dive_release_pass()
	_initialize_aircraft_release_states()
	state = State.DIVE_ENTRY
	return BeginDiveResult.STARTED


## Starts a dive from one complete attack solution. This is the AI entry
## point: every position (impact, release, dive entry), the attack direction
## and the locked dive direction come from the same solution.
##
## The snapshot is applied AFTER begin_dive_with_source, whose internal
## reset() would otherwise wipe positions set beforehand — that ordering bug
## is why individual setters must not be combined with begin_dive.
func begin_dive_with_solution(
		solution: DiveBombAttackSolution,
		source: AircraftSquadron.DiveControlSource,
		next_dispersion_radius_m: float = 0.0
) -> BeginDiveResult:
	if solution == null or not solution.valid:
		return BeginDiveResult.INVALID_CONFIGURATION
	var result := begin_dive_with_source(
		solution.predicted_impact_position,
		solution.target_velocity,
		source,
		next_dispersion_radius_m
	)
	if result in [
		BeginDiveResult.STARTED,
		BeginDiveResult.ALREADY_ACTIVE_SAME_SOURCE,
	]:
		_apply_solution_snapshot(solution)
		_select_reference_aircraft()
	return result


## Whole-solution update: impact, release, entry, directions and timing always
## change together. Ignored once the dive is locked.
func update_attack_solution(
		next_solution: DiveBombAttackSolution
) -> void:
	if solution_locked:
		return
	if next_solution == null or not next_solution.valid:
		return
	if state not in [State.DIVE_ENTRY, State.DIVING, State.RELEASING]:
		return
	_apply_solution_snapshot(next_solution)


func _apply_solution_snapshot(solution: DiveBombAttackSolution) -> void:
	attack_solution = solution.duplicate_solution()
	has_attack_solution = true
	predicted_impact_position = solution.predicted_impact_position
	# Legacy consumers (pass-abort checks, pull-out floor) read
	# target_position; keep it aligned with the solved impact point.
	target_position = solution.predicted_impact_position
	target_velocity = solution.target_velocity
	planned_release_position = solution.release_position
	has_planned_release_position = true
	planned_dive_entry_position = solution.dive_entry_position
	locked_attack_direction = solution.attack_direction
	locked_dive_direction = _build_locked_dive_direction(
		solution.attack_direction
	)


## Fixed dive direction: computed once per solution, never re-normalized
## toward the release point in flight, so the dive angle cannot wander.
func _build_locked_dive_direction(attack_direction: Vector3) -> Vector3:
	var horizontal := attack_direction
	horizontal.y = 0.0
	if horizontal.length_squared() <= EPSILON:
		horizontal = owner_squadron.get_formation_forward() \
			if owner_squadron != null else Vector3.FORWARD
		horizontal.y = 0.0
	horizontal = horizontal.normalized() \
		if horizontal.length_squared() > EPSILON else Vector3.FORWARD
	var angle_rad := deg_to_rad(clampf(
		dive_data.dive_angle_degrees if dive_data != null else 55.0,
		1.0,
		89.0
	))
	return (
		horizontal * cos(angle_rad)
		+ Vector3.DOWN * sin(angle_rad)
	).normalized()


#region Reference aircraft
## The squadron's central aircraft: closest alive unit to the formation
## center. It anchors the release-window judgement for the whole squadron.
func get_reference_aircraft() -> AircraftUnit:
	var current: Variant = _reference_aircraft_ref.get_ref() \
		if _reference_aircraft_ref != null else null
	if current != null and is_instance_valid(current):
		var aircraft := current as AircraftUnit
		if aircraft != null and aircraft.is_alive():
			return aircraft
	# The reference was lost: pick a new central aircraft but keep the locked
	# solution — the dive trajectory itself does not change (spec policy).
	_select_reference_aircraft()
	var replacement: Variant = _reference_aircraft_ref.get_ref() \
		if _reference_aircraft_ref != null else null
	if replacement != null and is_instance_valid(replacement):
		return replacement as AircraftUnit
	return null


func _select_reference_aircraft() -> void:
	var selected: AircraftUnit = null
	if owner_squadron != null and is_instance_valid(owner_squadron):
		selected = owner_squadron.select_dive_bomb_reference_aircraft()
	_reference_aircraft_ref = weakref(selected) if selected != null else null
	_reference_aircraft_instance_id = selected.get_instance_id() \
		if selected != null else 0


func get_reference_aircraft_instance_id() -> int:
	return _reference_aircraft_instance_id
#endregion


## Supplies the solved release point. Optional: a caller that provides none
## (player manual dives) keeps the previous behaviour of flying at the impact
## point.
func set_planned_release_position(next_release_position: Vector3) -> void:
	if not next_release_position.is_finite():
		return
	if solution_locked:
		return
	planned_release_position = next_release_position
	has_planned_release_position = true


func update_target(
		next_target_position: Vector3,
		next_target_velocity: Vector3
) -> void:
	if solution_locked:
		return
	if state not in [State.DIVE_ENTRY, State.DIVING, State.RELEASING]:
		return
	target_position = next_target_position
	target_velocity = next_target_velocity

func is_solution_locked() -> bool:
	return solution_locked


func lock_solution() -> void:
	solution_locked = true

func update_dive(delta: float) -> void:
	if owner_squadron == null or not is_instance_valid(owner_squadron):
		state = State.FAILED
		return
	match state:
		State.DIVE_ENTRY:
			if owner_squadron.dive_control_source \
					== AircraftSquadron.DiveControlSource.AI \
					and not solution_locked:
				# The AI mission owns the final target refresh. Waiting here
				# guarantees that refresh happens before the dive commits.
				return
			state = State.DIVING
		State.DIVING, State.RELEASING:
			_update_attack_descent(delta)
		State.PULLING_OUT:
			_update_pull_out(delta)
		State.IDLE, State.COMPLETED, State.FAILED:
			pass


func begin_pull_out() -> void:
	if state in [
		State.IDLE,
		State.PULLING_OUT,
		State.COMPLETED,
		State.FAILED,
	]:
		return
	for aircraft_id_value in _aircraft_release_states.keys():
		var aircraft_id := int(aircraft_id_value)
		if int(_aircraft_release_states[aircraft_id]) \
				== AircraftReleaseState.PENDING:
			_aircraft_release_states[aircraft_id] = \
				AircraftReleaseState.FAILED
	_pull_out_forward = owner_squadron.get_formation_forward()
	_pull_out_forward.y = 0.0
	if _pull_out_forward.length_squared() <= EPSILON:
		_pull_out_forward = Vector3.FORWARD
	else:
		_pull_out_forward = _pull_out_forward.normalized()
	_release_completion_wait_left = maxf(
		payload_release_settings.completion_wait_sec \
			if payload_release_settings != null else 0.5,
		0.0
	)
	state = State.PULLING_OUT
	_update_release_state_counts()
	_finish_release_pass_if_resolved()


func cancel() -> void:
	if state == State.IDLE:
		return
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.cancel_pending_weapon_release()
		for aircraft_id_value in _aircraft_release_states.keys():
			var aircraft_id := int(aircraft_id_value)
			if int(_aircraft_release_states[aircraft_id]) in [
				AircraftReleaseState.PENDING,
				AircraftReleaseState.REQUESTED,
			]:
				_aircraft_release_states[aircraft_id] = \
					AircraftReleaseState.FAILED
		_release_pass_cancelled = true
		_finish_release_pass(true)
		owner_squadron.restore_formation_flight()
		owner_squadron.dive_control_source = \
			AircraftSquadron.DiveControlSource.NONE
	if state != State.COMPLETED:
		state = State.FAILED
	release_block_reason = ReleaseBlockReason.CANCELLED


func get_state() -> int:
	return int(state)


func is_active() -> bool:
	return state in [
		State.DIVE_ENTRY,
		State.DIVING,
		State.RELEASING,
		State.PULLING_OUT,
	]


func did_release_any_bomb() -> bool:
	return _released_aircraft_count > 0


func get_release_block_reason() -> ReleaseBlockReason:
	return release_block_reason


func get_release_aircraft_count() -> int:
	return _aircraft_release_states.size()


func get_aircraft_release_state(aircraft: AircraftUnit) -> int:
	if aircraft == null or not is_instance_valid(aircraft):
		return int(AircraftReleaseState.SKIPPED)
	return int(_aircraft_release_states.get(
		aircraft.get_instance_id(),
		AircraftReleaseState.SKIPPED
	))


func get_attack_result_data() -> DiveAttackResult:
	var result := DiveAttackResult.new()
	var squadron_result: AircraftPayloadReleasePassResult
	if _release_pass_finished \
			and owner_squadron != null \
			and is_instance_valid(owner_squadron):
		squadron_result = owner_squadron \
			.get_last_payload_release_result()
	result.released_count = squadron_result.released_count \
		if squadron_result != null else _released_aircraft_count
	result.successful = result.released_count > 0
	result.release_started = _total_release_request_count > 0
	result.release_failed = result.released_count <= 0 \
		and (_failed_aircraft_count > 0 \
			or _skipped_aircraft_count > 0)
	result.requested_count = squadron_result.requested_count \
		if squadron_result != null else _total_release_request_count
	result.failed_count = squadron_result.failed_count \
		if squadron_result != null else _failed_aircraft_count
	result.skipped_count = squadron_result.skipped_count \
		if squadron_result != null else _skipped_aircraft_count
	result.cancelled = squadron_result.cancelled \
		if squadron_result != null else _release_pass_cancelled
	result.remaining_ammunition = owner_squadron \
		.get_total_remaining_ammunition() \
		if owner_squadron != null \
		and is_instance_valid(owner_squadron) else 0
	result.final_state = State.keys()[int(state)]
	return result


func get_lowest_alive_aircraft_altitude() -> float:
	if owner_squadron == null or not is_instance_valid(owner_squadron):
		return 0.0
	var lowest := INF
	for aircraft in owner_squadron.get_alive_aircraft():
		lowest = minf(lowest, _get_aircraft_altitude(aircraft))
	return lowest if lowest != INF else 0.0


func get_highest_alive_aircraft_altitude() -> float:
	if owner_squadron == null or not is_instance_valid(owner_squadron):
		return 0.0
	var highest := -INF
	for aircraft in owner_squadron.get_alive_aircraft():
		highest = maxf(highest, _get_aircraft_altitude(aircraft))
	return highest if highest != -INF else 0.0


func get_debug_snapshot() -> Dictionary:
	var control_source := "NONE"
	if owner_squadron != null and is_instance_valid(owner_squadron):
		control_source = AircraftSquadron.DiveControlSource.keys()[
			int(owner_squadron.dive_control_source)
		]
	var aircraft_states := {}
	var aircraft_altitudes := {}
	var retry_counts := {}
	for aircraft_id_value in _aircraft_release_states.keys():
		var aircraft_id := int(aircraft_id_value)
		var release_state := int(_aircraft_release_states[aircraft_id])
		aircraft_states[aircraft_id] = \
			AircraftReleaseState.keys()[release_state]
		retry_counts[aircraft_id] = int(
			_aircraft_release_attempts.get(aircraft_id, 0)
		)
	if owner_squadron != null and is_instance_valid(owner_squadron):
		for aircraft in owner_squadron.get_alive_aircraft():
			var aircraft_id := aircraft.get_instance_id()
			aircraft_altitudes[aircraft_id] = \
				_get_aircraft_altitude(aircraft)
	var squadron_released_count := 0
	if owner_squadron != null and is_instance_valid(owner_squadron):
		if _release_pass_finished:
			var pass_result := owner_squadron.get_last_payload_release_result()
			squadron_released_count = pass_result.released_count \
				if pass_result != null else 0
		else:
			squadron_released_count = owner_squadron \
				.payload_release_coordinator \
				.get_active_completed_count()
	return {
		"state": State.keys()[int(state)],
		"control_source": control_source,
		"target_position": target_position,
		"target_velocity": target_velocity,
		"dive_elapsed_time": dive_elapsed_seconds,
		"pending_aircraft_count": _pending_aircraft_count,
		"requested_aircraft_count": _requested_aircraft_count,
		"total_release_request_count": _total_release_request_count,
		"released_aircraft_count": _released_aircraft_count,
		"squadron_actual_released_count": squadron_released_count,
		"release_result_mismatch":
			_release_pass_finished \
			and _released_aircraft_count != squadron_released_count,
		"failed_aircraft_count": _failed_aircraft_count,
		"skipped_aircraft_count": _skipped_aircraft_count,
		"aircraft_altitudes": aircraft_altitudes,
		"aircraft_release_states": aircraft_states,
		"aircraft_retry_counts": retry_counts,
		"pull_out_ratio":
			dive_data.pull_out_aircraft_ratio \
			if dive_data != null else 0.0,
		"release_completion_wait":
			_release_completion_wait_left,
		"target_passed": _has_passed_target() \
			if owner_squadron != null \
			and is_instance_valid(owner_squadron) else false,
		"target_pass_margin":
			dive_data.target_pass_margin_m \
			if dive_data != null else 0.0,
		"remaining_ammunition":
			owner_squadron.get_total_remaining_ammunition() \
			if owner_squadron != null \
			and is_instance_valid(owner_squadron) else 0,
		"release_failure_reason":
			ReleaseBlockReason.keys()[int(release_block_reason)],
		"has_attack_solution": has_attack_solution,
		"solution_locked": solution_locked,
		"predicted_impact_position": predicted_impact_position,
		"planned_release_position": planned_release_position,
		"planned_dive_entry_position": planned_dive_entry_position,
		"locked_attack_direction": locked_attack_direction,
		"locked_dive_direction": locked_dive_direction,
		"reference_aircraft_id": _reference_aircraft_instance_id,
		"solution_revision": attack_solution.revision \
			if attack_solution != null else 0,
	}


func _update_attack_descent(delta: float) -> void:
	dive_elapsed_seconds += maxf(delta, 0.0)
	_update_release_retry_timers(delta)
	_update_individual_aircraft_release()
	if not _has_unresolved_aircraft_release():
		begin_pull_out()
		return
	if _should_begin_group_pull_out() \
			or _should_abort_after_passing_target():
		release_block_reason = ReleaseBlockReason.SAFETY_ALTITUDE_REACHED
		begin_pull_out()
		return
	_apply_dive_flight(delta)


func _update_individual_aircraft_release() -> void:
	if has_attack_solution:
		_update_central_release_window()
		return
	_update_legacy_altitude_release()


#region Central release window
## Judges the whole squadron's release from the reference aircraft. When the
## window opens every pending aircraft drops its real bomb at once; when the
## reference falls below the minimum release altitude without a valid window,
## the pass is abandoned with ammunition intact instead of force-dropping.
func _update_central_release_window() -> void:
	if not _has_pending_aircraft_release():
		return
	var reference := get_reference_aircraft()
	if reference == null:
		release_block_reason = ReleaseBlockReason.REFERENCE_AIRCRAFT_LOST
		_skip_all_pending_releases()
		return
	var reason := _evaluate_reference_release_window(reference)
	release_block_reason = reason
	if reason == ReleaseBlockReason.NONE:
		for aircraft_id_value in _aircraft_release_states.keys():
			var aircraft_id := int(aircraft_id_value)
			if int(_aircraft_release_states[aircraft_id]) \
					!= AircraftReleaseState.PENDING:
				continue
			var aircraft := _find_alive_aircraft(aircraft_id)
			if aircraft == null:
				_aircraft_release_states[aircraft_id] = \
					AircraftReleaseState.FAILED
				continue
			_attempt_individual_release(aircraft)
		_update_release_state_counts()
		return
	var reference_altitude := reference.global_position.y \
		- predicted_impact_position.y
	if reference_altitude < maxf(dive_data.minimum_release_altitude_m, 0.0):
		# The last altitude at which a drop was allowed has passed without a
		# valid horizontal solution: give up rather than waste bombs.
		_skip_all_pending_releases()


## Everything the reference aircraft must satisfy before the squadron drops.
## Ordered cheapest-first; the first violated condition is reported.
func _evaluate_reference_release_window(
		reference: AircraftUnit
) -> ReleaseBlockReason:
	if dive_elapsed_seconds \
			< maxf(dive_data.minimum_dive_time_before_release_sec, 0.0):
		return ReleaseBlockReason.TOO_EARLY
	var altitude := reference.global_position.y - predicted_impact_position.y
	if altitude > dive_data.automatic_release_altitude_m \
			+ maxf(dive_data.release_altitude_tolerance_m, 0.0):
		return ReleaseBlockReason.TOO_EARLY
	var release_offset := reference.global_position \
		- planned_release_position
	release_offset.y = 0.0
	if release_offset.length() \
			> maxf(dive_data.release_position_tolerance_m, 0.0):
		return ReleaseBlockReason.RELEASE_POSITION_MISSED
	var reference_forward := reference.velocity
	reference_forward.y = 0.0
	if reference_forward.length_squared() <= EPSILON:
		reference_forward = -reference.global_transform.basis.z
		reference_forward.y = 0.0
	if reference_forward.length_squared() > EPSILON:
		reference_forward = reference_forward.normalized()
		var heading_dot := clampf(
			reference_forward.dot(locked_attack_direction),
			-1.0,
			1.0
		)
		if rad_to_deg(acos(heading_dot)) > maxf(
			dive_data.maximum_release_heading_error_degrees,
			0.0
		):
			return ReleaseBlockReason.HEADING_NOT_ALIGNED
	var weapon_data := _get_bomb_weapon_data()
	if weapon_data != null:
		var predicted_now := DiveBombBallistics \
			.predict_impact_from_release_state(
				reference.global_position,
				DiveBombBallistics.resolve_bomb_initial_velocity(
					reference.velocity,
					weapon_data
				),
				predicted_impact_position.y,
				weapon_data,
				_get_world_gravity()
			)
		if not predicted_now.is_finite():
			return ReleaseBlockReason.IMPACT_SOLUTION_INVALID
		var impact_offset := predicted_now - predicted_impact_position
		impact_offset.y = 0.0
		if impact_offset.length() \
				> maxf(dive_data.maximum_predicted_impact_error_m, 0.0):
			return ReleaseBlockReason.IMPACT_SOLUTION_INVALID
	return ReleaseBlockReason.NONE


## Marks every pending aircraft as skipped: no release request is sent, so
## ammunition stays aboard and the pass resolves into a pull-out.
func _skip_all_pending_releases() -> void:
	for aircraft_id_value in _aircraft_release_states.keys():
		var aircraft_id := int(aircraft_id_value)
		if int(_aircraft_release_states[aircraft_id]) \
				== AircraftReleaseState.PENDING:
			_aircraft_release_states[aircraft_id] = \
				AircraftReleaseState.SKIPPED
	_update_release_state_counts()


func _has_pending_aircraft_release() -> bool:
	for value in _aircraft_release_states.values():
		if int(value) == AircraftReleaseState.PENDING:
			return true
	return false


func _get_bomb_weapon_data() -> AircraftWeaponData:
	var data := owner_squadron.squadron_data.aircraft_data \
		if owner_squadron != null \
		and owner_squadron.squadron_data != null else null
	return data.weapon_data if data != null else null


func _get_world_gravity() -> float:
	return float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
#endregion


func _update_legacy_altitude_release() -> void:
	for aircraft_id_value in _aircraft_release_states.keys():
		var aircraft_id := int(aircraft_id_value)
		var release_state := int(_aircraft_release_states[aircraft_id])
		if release_state != AircraftReleaseState.PENDING:
			continue
		var aircraft := _find_alive_aircraft(aircraft_id)
		if aircraft == null:
			_aircraft_release_states[aircraft_id] = \
				AircraftReleaseState.FAILED
			continue
		var altitude := _get_aircraft_altitude(aircraft)
		if float(_aircraft_release_retry_left.get(
					aircraft_id,
					0.0
				)) > 0.0:
			_previous_aircraft_altitudes[aircraft_id] = altitude
			continue
		var previous_altitude := float(
			_previous_aircraft_altitudes.get(
				aircraft_id,
				altitude
			)
		)
		var decision := release_policy.evaluate(
			altitude,
			previous_altitude,
			dive_elapsed_seconds,
			dive_data
		)
		if decision == DiveReleasePolicy.Decision.WAIT:
			_previous_aircraft_altitudes[aircraft_id] = altitude
			continue
		if decision == DiveReleasePolicy.Decision.MISSED_WINDOW:
			_aircraft_release_states[aircraft_id] = \
				AircraftReleaseState.FAILED
			_previous_aircraft_altitudes[aircraft_id] = altitude
			continue
		_attempt_individual_release(aircraft)
		_previous_aircraft_altitudes[aircraft_id] = altitude
	_update_release_state_counts()


func _attempt_individual_release(aircraft: AircraftUnit) -> void:
	var aircraft_id := aircraft.get_instance_id()
	var scatter_offset := _aircraft_scatter_offsets.get(
		aircraft_id,
		Vector3.ZERO
	) as Vector3
	var context := AircraftPayloadReleaseContext.create(
		target_position + scatter_offset,
		target_velocity
	)
	var result := owner_squadron.request_aircraft_payload_release(
		aircraft,
		context
	)
	match result.status:
		AircraftPayloadReleaseRequestResult.Status.QUEUED, \
				AircraftPayloadReleaseRequestResult.Status.ALREADY_PENDING:
			if result.status \
					== AircraftPayloadReleaseRequestResult.Status.QUEUED:
				_total_release_request_count += 1
			_aircraft_release_states[aircraft_id] = \
				AircraftReleaseState.REQUESTED
			state = State.RELEASING
		AircraftPayloadReleaseRequestResult.Status.ALREADY_RELEASED:
			_aircraft_release_states[aircraft_id] = \
				AircraftReleaseState.RELEASED
		AircraftPayloadReleaseRequestResult.Status.RETRYABLE:
			var retry_count := int(_aircraft_release_attempts.get(
				aircraft_id,
				0
			))
			var maximum_retries := payload_release_settings \
				.maximum_additional_retries \
				if payload_release_settings != null else 3
			if retry_count >= maxi(maximum_retries, 0):
				_aircraft_release_states[aircraft_id] = \
					AircraftReleaseState.FAILED
			else:
				_aircraft_release_attempts[aircraft_id] = \
					retry_count + 1
				_aircraft_release_retry_left[aircraft_id] = maxf(
					payload_release_settings.retry_interval_sec \
						if payload_release_settings != null else 0.05,
					0.0
				)
		AircraftPayloadReleaseRequestResult.Status.NO_AMMUNITION:
			_aircraft_release_states[aircraft_id] = \
				AircraftReleaseState.SKIPPED
		AircraftPayloadReleaseRequestResult.Status.NO_WEAPON_CONTROLLER, \
				AircraftPayloadReleaseRequestResult.Status.WEAPON_DISABLED, \
				AircraftPayloadReleaseRequestResult.Status.INVALID_AIRCRAFT:
			_aircraft_release_states[aircraft_id] = \
				AircraftReleaseState.FAILED


func _update_release_retry_timers(delta: float) -> void:
	for aircraft_id in _aircraft_release_retry_left.keys():
		_aircraft_release_retry_left[aircraft_id] = maxf(
			float(_aircraft_release_retry_left[aircraft_id])
				- maxf(delta, 0.0),
			0.0
		)


func _initialize_aircraft_release_states() -> void:
	_aircraft_release_states.clear()
	_aircraft_release_attempts.clear()
	_aircraft_release_retry_left.clear()
	_previous_aircraft_altitudes.clear()
	_aircraft_scatter_offsets.clear()
	for aircraft in owner_squadron.get_alive_aircraft():
		var aircraft_id := aircraft.get_instance_id()
		_aircraft_scatter_offsets[aircraft_id] = _random_scatter_offset()
		var release_state := AircraftReleaseState.PENDING
		if aircraft.weapon_controller == null:
			release_state = AircraftReleaseState.FAILED
		elif aircraft.weapon_controller.weapon_data == null:
			release_state = AircraftReleaseState.FAILED
		elif aircraft.weapon_controller.weapon_data.weapon_type \
				!= AircraftWeaponData.WeaponType.BOMB:
			release_state = AircraftReleaseState.SKIPPED
		elif not aircraft.weapon_controller.has_ammunition():
			release_state = AircraftReleaseState.SKIPPED
		_aircraft_release_states[aircraft_id] = release_state
		_aircraft_release_attempts[aircraft_id] = 0
		_aircraft_release_retry_left[aircraft_id] = 0.0
		_previous_aircraft_altitudes[aircraft_id] = \
			_get_aircraft_altitude(aircraft)
	_update_release_state_counts()


func _get_aircraft_altitude(aircraft: AircraftUnit) -> float:
	return aircraft.global_position.y - target_position.y


func _find_alive_aircraft(aircraft_id: int) -> AircraftUnit:
	for aircraft in owner_squadron.get_alive_aircraft():
		if aircraft.get_instance_id() == aircraft_id:
			return aircraft
	return null


func _has_unresolved_aircraft_release() -> bool:
	for value in _aircraft_release_states.values():
		if int(value) in [
			AircraftReleaseState.PENDING,
			AircraftReleaseState.REQUESTED,
		]:
			return true
	return false


func _has_requested_aircraft_release() -> bool:
	for value in _aircraft_release_states.values():
		if int(value) == AircraftReleaseState.REQUESTED:
			return true
	return false


func _should_begin_group_pull_out() -> bool:
	var alive := owner_squadron.get_alive_aircraft()
	if alive.is_empty():
		return true
	var below_count := 0
	for aircraft in alive:
		if _get_aircraft_altitude(aircraft) \
				<= dive_data.automatic_pull_out_altitude_m:
			below_count += 1
	return float(below_count) / float(alive.size()) \
		>= clampf(dive_data.pull_out_aircraft_ratio, 0.1, 1.0)


func _has_passed_target() -> bool:
	var alive := owner_squadron.get_alive_aircraft()
	if alive.is_empty():
		return true
	var average_position := Vector3.ZERO
	for aircraft in alive:
		average_position += aircraft.global_position
	average_position /= float(alive.size())
	var offset := target_position - average_position
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	if horizontal.length_squared() <= EPSILON:
		return false
	var forward := owner_squadron.get_formation_forward()
	forward.y = 0.0
	if forward.length_squared() <= EPSILON:
		return false
	return forward.normalized().dot(horizontal.normalized()) < 0.0


func _should_abort_after_passing_target() -> bool:
	if not _has_passed_target():
		return false
	if dive_data.require_release_attempt_before_pass_abort \
			and _total_release_request_count <= 0:
		return false
	var alive := owner_squadron.get_alive_aircraft()
	if alive.is_empty():
		return true
	var average_position := Vector3.ZERO
	for aircraft in alive:
		average_position += aircraft.global_position
	average_position /= float(alive.size())
	var horizontal_offset := Vector3(
		target_position.x - average_position.x,
		0.0,
		target_position.z - average_position.z
	)
	if horizontal_offset.length() <= maxf(
		dive_data.target_pass_margin_m,
		0.0
	):
		return false
	var average_altitude := average_position.y - target_position.y
	return average_altitude \
		<= maxf(dive_data.target_pass_check_max_altitude_m, 0.0)


func _update_release_state_counts() -> void:
	_pending_aircraft_count = 0
	_requested_aircraft_count = 0
	_released_aircraft_count = 0
	_failed_aircraft_count = 0
	_skipped_aircraft_count = 0
	for value in _aircraft_release_states.values():
		match int(value):
			AircraftReleaseState.PENDING:
				_pending_aircraft_count += 1
			AircraftReleaseState.REQUESTED:
				_requested_aircraft_count += 1
			AircraftReleaseState.RELEASED:
				_released_aircraft_count += 1
			AircraftReleaseState.FAILED:
				_failed_aircraft_count += 1
			AircraftReleaseState.SKIPPED:
				_skipped_aircraft_count += 1


func _on_aircraft_weapon_release_finished(
		aircraft_id: int,
		_aircraft: AircraftUnit,
		success: bool,
		cancelled: bool,
		reason: int
) -> void:
	if not _aircraft_release_states.has(aircraft_id):
		return
	_aircraft_release_states[aircraft_id] = (
		AircraftReleaseState.RELEASED
		if success else AircraftReleaseState.FAILED
	)
	_release_pass_cancelled = _release_pass_cancelled or cancelled
	_update_release_state_counts()
	if success:
		release_block_reason = ReleaseBlockReason.NONE
		aircraft_automatic_release_completed.emit(
			aircraft_id,
			_released_aircraft_count,
			_aircraft_release_states.size()
		)
	elif not cancelled:
		aircraft_automatic_release_failed.emit(
			aircraft_id,
			reason
		)
	if state == State.PULLING_OUT:
		_finish_release_pass_if_resolved()


func _finish_release_pass_if_resolved() -> void:
	if not _has_requested_aircraft_release():
		_finish_release_pass(_release_pass_cancelled)


func _finish_release_pass(cancelled: bool) -> void:
	if _release_pass_finished:
		return
	_update_release_state_counts()
	var controller_released_count := _released_aircraft_count
	_release_pass_finished = true
	_release_pass_cancelled = cancelled
	var actual_result := owner_squadron.finish_dive_release_pass(
		_failed_aircraft_count,
		_skipped_aircraft_count,
		cancelled
	)
	_released_aircraft_count = actual_result.released_count
	_failed_aircraft_count = actual_result.failed_count
	_skipped_aircraft_count = actual_result.skipped_count
	_release_pass_cancelled = actual_result.cancelled
	if _released_aircraft_count != controller_released_count:
		push_warning(
			"Dive release result mismatch: squadron=%d controller=%d"
			% [_released_aircraft_count, controller_released_count]
		)
	automatic_release_pass_completed.emit(
		_released_aircraft_count,
		_failed_aircraft_count,
		_skipped_aircraft_count,
		_release_pass_cancelled
	)


func _apply_dive_flight(delta: float) -> void:
	# Fly the dive toward the planned release point, not the impact point.
	if has_attack_solution \
			and locked_dive_direction.length_squared() > EPSILON:
		# Central-solution dive: fly the fixed direction computed at lock
		# time. The release point is a waypoint on this fixed trajectory,
		# never a per-frame steering target, so heading and dive angle stay
		# constant and match what the resolver assumed.
		owner_squadron.apply_direct_flight(
			locked_dive_direction,
			dive_data.dive_speed_mps,
			delta,
			target_position.y + maxf(
				dive_data.automatic_pull_out_altitude_m,
				0.0
			)
		)
		return
	# Legacy (solutionless) dive: steer toward the aim point each frame.
	# Flying at the impact point makes the aircraft overfly the target, because
	# the bomb still travels forward for its whole fall time after release.
	var dive_aim_point := planned_release_position \
		if has_planned_release_position else target_position
	var to_target := dive_aim_point - owner_squadron.formation_center
	var horizontal_direction := Vector3(to_target.x, 0.0, to_target.z)
	if horizontal_direction.length_squared() <= EPSILON:
		horizontal_direction = owner_squadron.get_formation_forward()
		horizontal_direction.y = 0.0
	horizontal_direction = horizontal_direction.normalized() \
		if horizontal_direction.length_squared() > EPSILON \
		else Vector3.FORWARD
	var angle_rad := deg_to_rad(clampf(
		dive_data.dive_angle_degrees,
		1.0,
		89.0
	))
	var dive_direction := (
		horizontal_direction * cos(angle_rad)
		+ Vector3.DOWN * sin(angle_rad)
	).normalized()
	owner_squadron.apply_direct_flight(
		dive_direction,
		dive_data.dive_speed_mps,
		delta,
		target_position.y + maxf(
			dive_data.automatic_pull_out_altitude_m,
			0.0
		)
	)


func _update_pull_out(delta: float) -> void:
	if _has_requested_aircraft_release():
		_release_completion_wait_left = maxf(
			_release_completion_wait_left - maxf(delta, 0.0),
			0.0
		)
		if _release_completion_wait_left <= 0.0:
			for aircraft_id_value in _aircraft_release_states.keys():
				var aircraft_id := int(aircraft_id_value)
				if int(_aircraft_release_states[aircraft_id]) \
						== AircraftReleaseState.REQUESTED:
					owner_squadron.cancel_aircraft_weapon_release(
						aircraft_id
					)
			_finish_release_pass_if_resolved()
	else:
		_finish_release_pass_if_resolved()
	var angle_rad := deg_to_rad(clampf(
		dive_data.pull_out_climb_angle_degrees,
		1.0,
		89.0
	))
	var climb_direction := (
		_pull_out_forward * cos(angle_rad)
		+ Vector3.UP * sin(angle_rad)
	).normalized()
	owner_squadron.apply_direct_flight(
		climb_direction,
		dive_data.dive_speed_mps,
		delta,
		target_position.y
	)
	var data := owner_squadron.squadron_data.aircraft_data
	var carrier := owner_squadron.get_owner_carrier()
	var desired_altitude := (
		carrier.global_position.y if carrier != null else target_position.y
	) + data.operating_altitude_m
	if owner_squadron.formation_center.y \
			>= desired_altitude - maxf(data.arrival_distance_m, 1.0) \
			and not _has_requested_aircraft_release():
		_finish_release_pass_if_resolved()
		owner_squadron.finish_direct_flight_holding(desired_altitude)
		state = State.COMPLETED


func _is_valid_dive_squadron() -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.DIVE_BOMBER \
		and dive_data != null \
		and dive_data.validate().is_empty()


func set_random_seed_for_test(seed_value: int) -> void:
	_rng.seed = seed_value
	_rng_seed_overridden = true


func _random_scatter_offset() -> Vector3:
	if dispersion_radius_m <= 0.0:
		return Vector3.ZERO
	var angle := _rng.randf() * TAU
	var distance := sqrt(_rng.randf()) * dispersion_radius_m
	return Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
