extends RefCounted
class_name InterceptMissionBehavior

enum State {
	INTERCEPTING,
	ALIGNING,
	FIRING,
	SEPARATING,
	REACQUIRING,
	RETURNING,
	COMPLETED,
	FAILED,
}

const EPSILON := 0.0001
const MAXIMUM_PREDICTION_SECONDS := 8.0
const MINIMUM_FIRING_WINDOW_SECONDS := 0.9
const REQUIRED_FIRED_RATIO := 0.6

var owner_squadron: AircraftSquadron
var mission_data: AirMissionData
var state: State = State.FAILED
var attack_pass := 0
var successful := false

var _target_squadron_ref: WeakRef
var _combat_rng := RandomNumberGenerator.new()
var _separation_destination := Vector3.ZERO
var _finished := true
var _firing_time_left := 0.0
var _aircraft_fired_this_pass: Dictionary = {}


func setup(
		next_owner_squadron: AircraftSquadron,
		target_squadron: AircraftSquadron,
		next_mission_data: AirMissionData,
		rng_seed: int
) -> bool:
	owner_squadron = next_owner_squadron
	mission_data = next_mission_data
	if not _is_valid_setup(target_squadron):
		state = State.FAILED
		_finished = true
		return false
	_target_squadron_ref = weakref(target_squadron)
	_combat_rng.seed = rng_seed if rng_seed != 0 else (
		owner_squadron.get_instance_id()
		^ target_squadron.get_instance_id()
		^ Time.get_ticks_msec()
	)
	state = State.INTERCEPTING
	attack_pass = 0
	successful = false
	_finished = false
	_firing_time_left = 0.0
	_aircraft_fired_this_pass.clear()
	owner_squadron.set_combat_formation_enabled(true)
	var coordinator := owner_squadron.get_combat_coordinator()
	if coordinator != null:
		coordinator.register_intercept_assignment(
			owner_squadron,
			target_squadron
		)
	return true


func update(delta: float) -> void:
	if _finished or owner_squadron == null \
			or not is_instance_valid(owner_squadron):
		return
	var target := get_target_squadron()
	if target == null or target.get_alive_aircraft_count() <= 0:
		_finish_and_return(true)
		return
	if owner_squadron.get_alive_aircraft_count() <= 0:
		_finish_without_return(false)
		return
	if owner_squadron.get_owner_carrier() == null:
		_finish_without_return(false)
		return
	if _is_target_outside_operating_radius(target):
		_finish_and_return(false)
		return
	if not owner_squadron.has_any_ammunition():
		_finish_and_return(false)
		return
	match state:
		State.INTERCEPTING:
			_update_intercepting(target)
		State.ALIGNING:
			_update_aligning(target)
		State.FIRING:
			_update_firing(target, delta)
		State.SEPARATING:
			_update_separating()
		State.REACQUIRING:
			_begin_intercepting()
		State.RETURNING, State.COMPLETED, State.FAILED:
			pass


func cancel_and_return() -> void:
	if not _finished:
		_finish_and_return(false)


func cancel_without_return() -> void:
	if not _finished:
		_finish_without_return(false)


func get_state() -> int:
	return int(state)


func get_target_squadron() -> AircraftSquadron:
	if _target_squadron_ref == null:
		return null
	var target := _target_squadron_ref.get_ref() as AircraftSquadron
	if target == null or not is_instance_valid(target) \
			or target.is_queued_for_deletion() \
			or target.state in [
				AircraftSquadron.State.RECOVERING,
				AircraftSquadron.State.DESTROYED,
			]:
		return null
	return target


func is_finished() -> bool:
	return _finished


func get_debug_snapshot() -> Dictionary:
	var target := get_target_squadron()
	return {
		"state": State.keys()[int(state)],
		"target_squadron": target.name if target != null else "",
		"attack_pass": attack_pass,
		"alive_attackers": owner_squadron.get_alive_aircraft_count() \
			if owner_squadron != null \
			and is_instance_valid(owner_squadron) else 0,
		"alive_targets": target.get_alive_aircraft_count() \
			if target != null else 0,
		"mission_distance":
			owner_squadron.formation_center.distance_to(
				target.formation_center
			) if owner_squadron != null \
			and is_instance_valid(owner_squadron) \
			and target != null else 0.0,
	}


func _update_intercepting(target: AircraftSquadron) -> void:
	var fighter_data := owner_squadron.get_fighter_combat_data()
	var speed := maxf(
		owner_squadron.get_formation_velocity().length(),
		1.0
	)
	var distance := owner_squadron.formation_center.distance_to(
		target.formation_center
	)
	var prediction_seconds := clampf(
		distance / speed,
		0.0,
		MAXIMUM_PREDICTION_SECONDS
	)
	var predicted_center := target.formation_center \
		+ target.get_formation_velocity() * prediction_seconds
	predicted_center.y = target.formation_center.y
	owner_squadron.set_mission_destination(predicted_center)
	if distance <= maxf(fighter_data.detection_range_m * 0.55, 600.0):
		state = State.ALIGNING


func _update_aligning(target: AircraftSquadron) -> void:
	var fighter_data := owner_squadron.get_fighter_combat_data()
	var target_forward := target.get_formation_forward()
	if target_forward.length_squared() <= EPSILON:
		target_forward = target.formation_center \
			- owner_squadron.formation_center
		target_forward = target_forward.normalized() \
			if target_forward.length_squared() > EPSILON \
			else Vector3.FORWARD
	var alignment_position := target.formation_center \
		- target_forward * fighter_data.preferred_engagement_range_m
	alignment_position.y = target.formation_center.y
	owner_squadron.set_mission_destination(alignment_position)
	var distance := owner_squadron.formation_center.distance_to(
		target.formation_center
	)
	if distance <= fighter_data.preferred_engagement_range_m * 1.5:
		owner_squadron.assign_fighter_targets(target)
		_begin_firing_window()
		state = State.FIRING


func _update_firing(
		target: AircraftSquadron,
		delta: float
) -> void:
	_firing_time_left = maxf(0.0, _firing_time_left - maxf(delta, 0.0))
	owner_squadron.set_mission_destination(
		target.formation_center + target.get_formation_velocity() * 0.5
	)
	owner_squadron.assign_fighter_targets(target)
	var results := owner_squadron.update_fighter_combat(
		delta,
		_combat_rng
	)
	for result in results:
		if result.valid and result.rounds_fired > 0:
			_aircraft_fired_this_pass[result.attacker_instance_id] = true
	var alive_count := owner_squadron.get_alive_aircraft_count()
	var required_count := maxi(
		1,
		ceili(float(alive_count) * REQUIRED_FIRED_RATIO)
	)
	var target_offset := target.formation_center \
		- owner_squadron.formation_center
	var target_passed := target_offset.length_squared() > EPSILON \
		and owner_squadron.get_formation_forward().dot(
			target_offset.normalized()
		) < -0.2
	var too_close := target_offset.length() \
		< owner_squadron.get_fighter_combat_data() \
			.preferred_engagement_range_m * 0.35
	if _firing_time_left <= 0.0 \
			or _aircraft_fired_this_pass.size() >= required_count \
			or target_passed \
			or too_close \
			or not owner_squadron.has_any_ammunition():
		_begin_separation()
		return
	if owner_squadron.formation_center.distance_to(
		target.formation_center
	) > owner_squadron.get_fighter_combat_data().disengage_range_m:
		state = State.ALIGNING


func _begin_separation() -> void:
	attack_pass += 1
	var fighter_data := owner_squadron.get_fighter_combat_data()
	var forward := owner_squadron.get_formation_forward()
	if forward.length_squared() <= EPSILON:
		forward = Vector3.FORWARD
	_separation_destination = owner_squadron.formation_center \
		+ forward.normalized() * fighter_data.separation_distance_m
	_separation_destination.y = owner_squadron.formation_center.y
	owner_squadron.clear_fighter_targets()
	owner_squadron.set_mission_destination(_separation_destination)
	state = State.SEPARATING


func _update_separating() -> void:
	if owner_squadron.state != AircraftSquadron.State.HOLDING:
		return
	var maximum_passes := mini(
		owner_squadron.get_fighter_combat_data().maximum_attack_passes,
		maxi(mission_data.attack_pass_count, 1)
	)
	if attack_pass >= maximum_passes \
			or not owner_squadron.has_any_ammunition():
		_finish_and_return(false)
		return
	state = State.REACQUIRING


func _begin_intercepting() -> void:
	state = State.INTERCEPTING


func _begin_firing_window() -> void:
	var gun_data: AircraftGunData
	var weapon_data := owner_squadron.get_aircraft_weapon_data()
	if weapon_data != null:
		gun_data = weapon_data.gun_data
	var burst_duration := gun_data.get_burst_duration_sec() \
		if gun_data != null else 0.0
	_firing_time_left = maxf(
		MINIMUM_FIRING_WINDOW_SECONDS,
		burst_duration + (
			gun_data.burst_cooldown_sec if gun_data != null else 0.0
		)
	)
	_aircraft_fired_this_pass.clear()


func _finish_and_return(was_successful: bool) -> void:
	successful = was_successful
	_finished = true
	state = State.COMPLETED if was_successful else State.FAILED
	_cleanup_assignment()
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.set_combat_formation_enabled(false)
		owner_squadron.clear_fighter_targets()
		state = State.RETURNING
		owner_squadron.request_return()


func _finish_without_return(was_successful: bool) -> void:
	successful = was_successful
	_finished = true
	state = State.COMPLETED if was_successful else State.FAILED
	_cleanup_assignment()
	if owner_squadron != null and is_instance_valid(owner_squadron):
		owner_squadron.set_combat_formation_enabled(false)
		owner_squadron.clear_fighter_targets()


func _cleanup_assignment() -> void:
	if owner_squadron == null or not is_instance_valid(owner_squadron):
		return
	var coordinator := owner_squadron.get_combat_coordinator()
	if coordinator != null:
		coordinator.unregister_intercept_assignment(owner_squadron)
	_target_squadron_ref = null


func _is_target_outside_operating_radius(
		target: AircraftSquadron
) -> bool:
	var carrier := owner_squadron.get_owner_carrier()
	var data := owner_squadron.squadron_data
	if carrier == null or data == null or data.aircraft_data == null:
		return true
	var radius := maxf(data.aircraft_data.combat_radius_m, 0.0)
	return carrier.global_position.distance_squared_to(
		target.formation_center
	) > radius * radius


func _is_valid_setup(target: AircraftSquadron) -> bool:
	return owner_squadron != null \
		and is_instance_valid(owner_squadron) \
		and owner_squadron.get_aircraft_role() \
			== AircraftData.AircraftRole.FIGHTER \
		and owner_squadron.get_fighter_combat_data() != null \
		and target != null \
		and is_instance_valid(target) \
		and target != owner_squadron \
		and FactionRelations.are_hostile(
			owner_squadron.get_team(),
			target.get_team()
		) \
		and mission_data != null \
		and mission_data.mission_type \
			== AirMissionData.MissionType.INTERCEPT_AIRCRAFT
