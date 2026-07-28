extends RefCounted
class_name FighterCombatResolver

const EPSILON := 0.0001
const RELATIVE_SPEED_REFERENCE_MPS := 500.0
const MINIMUM_RANGE_FACTOR := 0.2
const CLOSE_RANGE_FACTOR := 0.7


static func is_inside_firing_cone(
		attacker: AircraftUnit,
		target_position: Vector3,
		total_cone_degrees: float
) -> bool:
	if not _is_valid_aircraft(attacker) \
			or total_cone_degrees <= 0.0 \
			or total_cone_degrees > 180.0:
		return false
	var to_target := target_position - attacker.global_position
	if to_target.length_squared() <= EPSILON:
		return false
	var minimum_dot := cos(
		deg_to_rad(total_cone_degrees * 0.5)
	)
	return attacker.get_forward_direction().dot(
		to_target.normalized()
	) >= minimum_dot - EPSILON


static func calculate_hit_probability(
		attacker: AircraftUnit,
		target: AircraftUnit,
		fighter_data: FighterCombatData,
		gun_data: AircraftGunData
) -> FighterShotResult:
	return _calculate_hit_probability(
		attacker,
		target,
		fighter_data,
		gun_data,
		true
	)


static func resolve_burst(
		attacker: AircraftUnit,
		target: AircraftUnit,
		fighter_data: FighterCombatData,
		gun_data: AircraftGunData,
		rounds_fired: int,
		rng: RandomNumberGenerator
) -> FighterShotResult:
	var result := _calculate_hit_probability(
		attacker,
		target,
		fighter_data,
		gun_data,
		false
	)
	if not result.valid or rounds_fired <= 0 or rng == null:
		return result
	result.rounds_fired = rounds_fired
	for _index in range(rounds_fired):
		if rng.randf() <= result.hit_probability:
			result.hit_count += 1
	result.total_damage = float(result.hit_count) * gun_data.damage_per_hit
	return result


static func _calculate_hit_probability(
		attacker: AircraftUnit,
		target: AircraftUnit,
		fighter_data: FighterCombatData,
		gun_data: AircraftGunData,
		require_ammunition: bool
) -> FighterShotResult:
	var result := FighterShotResult.new()
	if not _is_valid_aircraft(attacker) \
			or not _is_valid_aircraft(target) \
			or attacker == target \
			or fighter_data == null \
			or gun_data == null \
			or not gun_data.is_valid_configuration() \
			or not FactionRelations.are_hostile(
				attacker.get_team(),
				target.get_team()
			):
		return result
	if require_ammunition and (
		attacker.weapon_controller == null
		or not attacker.weapon_controller.has_ammunition()
	):
		return result
	var to_target := target.global_position - attacker.global_position
	result.distance_m = to_target.length()
	if result.distance_m <= EPSILON \
			or result.distance_m > gun_data.effective_range_m:
		return result
	var target_direction := to_target / result.distance_m
	result.aim_dot = clampf(
		attacker.get_forward_direction().dot(target_direction),
		-1.0,
		1.0
	)
	var minimum_dot := cos(
		deg_to_rad(fighter_data.firing_cone_degrees * 0.5)
	)
	if result.aim_dot < minimum_dot - EPSILON:
		return result

	result.range_factor = _calculate_range_factor(
		result.distance_m,
		gun_data.optimal_range_m,
		gun_data.effective_range_m
	)
	var raw_angle_factor := clampf(
		inverse_lerp(minimum_dot, 1.0, result.aim_dot),
		0.0,
		1.0
	)
	var tracking_skill := clampf(
		fighter_data.tracking_skill,
		0.0,
		1.0
	)
	result.angle_factor = lerpf(
		raw_angle_factor,
		sqrt(raw_angle_factor),
		tracking_skill
	)
	result.angle_factor = pow(
		result.angle_factor,
		maxf(fighter_data.angular_accuracy_weight, 0.01)
	)
	result.pilot_factor = lerpf(
		0.65,
		1.25,
		clampf(fighter_data.pilot_skill, 0.0, 1.0)
	)
	var relative_velocity := target.get_world_velocity() \
		- attacker.get_world_velocity()
	result.relative_speed_factor = clampf(
		1.0
			- relative_velocity.length() / RELATIVE_SPEED_REFERENCE_MPS \
				* maxf(fighter_data.relative_speed_penalty, 0.0),
		0.4,
		1.0
	)
	var target_fighter_data := target.get_fighter_combat_data()
	var target_evasion := target_fighter_data.evasion_skill \
		if target_fighter_data != null else 0.25
	result.target_evasion_factor = lerpf(
		1.0,
		1.0 - clampf(fighter_data.target_evasion_weight, 0.0, 1.0),
		clampf(target_evasion, 0.0, 1.0)
	)
	var probability := fighter_data.base_accuracy \
		* gun_data.mechanical_accuracy \
		* result.pilot_factor \
		* result.range_factor \
		* result.angle_factor \
		* result.relative_speed_factor \
		* result.target_evasion_factor
	result.hit_probability = clampf(
		probability,
		clampf(fighter_data.minimum_accuracy, 0.0, 1.0),
		clampf(fighter_data.maximum_accuracy, 0.0, 1.0)
	)
	result.valid = true
	return result


static func _calculate_range_factor(
		distance_m: float,
		optimal_range_m: float,
		effective_range_m: float
) -> float:
	var optimal := maxf(optimal_range_m, EPSILON)
	var effective := maxf(effective_range_m, optimal)
	if distance_m <= optimal:
		var close_weight := smoothstep(0.0, optimal, distance_m)
		return lerpf(CLOSE_RANGE_FACTOR, 1.0, close_weight)
	var far_weight := smoothstep(
		optimal,
		effective,
		distance_m
	)
	return lerpf(1.0, MINIMUM_RANGE_FACTOR, far_weight)


static func _is_valid_aircraft(aircraft: AircraftUnit) -> bool:
	return aircraft != null \
		and is_instance_valid(aircraft) \
		and not aircraft.is_queued_for_deletion() \
		and aircraft.is_alive()
