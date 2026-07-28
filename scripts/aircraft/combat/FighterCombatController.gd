extends Node
class_name FighterCombatController

const EPSILON := 0.0001

var owner_aircraft: AircraftUnit
var fighter_data: FighterCombatData
var gun_data: AircraftGunData

var _target_ref: WeakRef
var _lock_time_left := 0.0
var _combat_enabled := false
var _last_result := FighterShotResult.new()


func setup(next_owner_aircraft: AircraftUnit) -> void:
	disable_combat()
	owner_aircraft = next_owner_aircraft
	if owner_aircraft == null or owner_aircraft.aircraft_data == null:
		return
	fighter_data = owner_aircraft.aircraft_data.fighter_combat_data
	var weapon_data := owner_aircraft.aircraft_data.weapon_data
	gun_data = weapon_data.gun_data \
		if weapon_data != null \
		and weapon_data.weapon_type \
			== AircraftWeaponData.WeaponType.AIR_TO_AIR_GUN else null
	_combat_enabled = _validate_configuration(true)


func set_target(target: AircraftUnit) -> void:
	if not _is_valid_hostile_target(target):
		clear_target()
		return
	var current := get_target()
	if current == target:
		return
	_target_ref = weakref(target)
	_lock_time_left = 0.0


func clear_target() -> void:
	_target_ref = null
	_lock_time_left = 0.0


func get_target() -> AircraftUnit:
	if _target_ref == null:
		return null
	var target := _target_ref.get_ref() as AircraftUnit
	if not _is_valid_hostile_target(target):
		clear_target()
		return null
	return target


func update_combat(
		delta: float,
		rng: RandomNumberGenerator
) -> FighterShotResult:
	_last_result = FighterShotResult.new()
	_set_result_attacker(_last_result)
	if not _combat_enabled or rng == null:
		return _last_result
	var target := get_target()
	if target == null \
			or owner_aircraft.weapon_controller == null \
			or not owner_aircraft.weapon_controller.can_fire_gun_burst():
		_lock_time_left = 0.0
		return _last_result
	var preview := FighterCombatResolver.calculate_hit_probability(
		owner_aircraft,
		target,
		fighter_data,
		gun_data
	)
	_set_result_attacker(preview)
	if not preview.valid:
		_lock_time_left = 0.0
		_last_result = preview
		return _last_result
	_lock_time_left += maxf(delta, 0.0)
	if _lock_time_left + EPSILON < maxf(fighter_data.lock_time_sec, 0.0):
		_last_result = preview
		return _last_result
	var rounds := owner_aircraft.weapon_controller.consume_gun_rounds(
		gun_data.rounds_per_burst
	)
	if rounds <= 0:
		_lock_time_left = 0.0
		return _last_result
	_last_result = FighterCombatResolver.resolve_burst(
		owner_aircraft,
		target,
		fighter_data,
		gun_data,
		rounds,
		rng
	)
	_set_result_attacker(_last_result)
	_lock_time_left = 0.0
	owner_aircraft.weapon_controller.begin_gun_burst_cooldown()
	if _last_result.total_damage > 0.0:
		var info := AircraftDamageInfo.new()
		info.source_aircraft = owner_aircraft
		info.source_squadron = owner_aircraft.get_parent() \
			as AircraftSquadron
		info.source_weapon_id = StringName(
			owner_aircraft.weapon_controller.weapon_data.id
		)
		info.hit_count = _last_result.hit_count
		info.hit_probability = _last_result.hit_probability
		target.apply_damage(_last_result.total_damage, info)
	owner_aircraft.weapon_controller.emit_gun_burst_result(
		target,
		_last_result
	)
	return _last_result


func can_engage_target() -> bool:
	return _combat_enabled \
		and get_target() != null \
		and owner_aircraft.weapon_controller != null \
		and owner_aircraft.weapon_controller.has_ammunition()


func is_target_in_firing_cone() -> bool:
	var target := get_target()
	return target != null \
		and fighter_data != null \
		and FighterCombatResolver.is_inside_firing_cone(
			owner_aircraft,
			target.global_position,
			fighter_data.firing_cone_degrees
		)


func is_target_in_range() -> bool:
	var target := get_target()
	return target != null \
		and gun_data != null \
		and owner_aircraft.global_position.distance_to(
			target.global_position
		) <= gun_data.effective_range_m


func reset_for_sortie() -> void:
	clear_target()
	_last_result = FighterShotResult.new()
	_combat_enabled = _validate_configuration(false)


func disable_combat() -> void:
	_combat_enabled = false
	clear_target()


func get_debug_snapshot() -> Dictionary:
	var target := get_target()
	var distance := owner_aircraft.global_position.distance_to(
		target.global_position
	) if target != null and owner_aircraft != null else 0.0
	return {
		"target_name": target.name if target != null else "",
		"distance": distance,
		"aim_dot": _last_result.aim_dot,
		"inside_firing_cone": is_target_in_firing_cone(),
		"inside_range": is_target_in_range(),
		"lock_progress": _lock_time_left,
		"remaining_ammunition":
			owner_aircraft.weapon_controller.get_remaining_ammunition() \
			if owner_aircraft != null \
			and owner_aircraft.weapon_controller != null else 0,
		"burst_cooldown":
			owner_aircraft.weapon_controller.gun_burst_cooldown_left \
			if owner_aircraft != null \
			and owner_aircraft.weapon_controller != null else 0.0,
		"last_hit_probability": _last_result.hit_probability,
		"last_hit_count": _last_result.hit_count,
	}


func _is_valid_hostile_target(target: AircraftUnit) -> bool:
	return target != null \
		and is_instance_valid(target) \
		and not target.is_queued_for_deletion() \
		and target.is_alive() \
		and owner_aircraft != null \
		and is_instance_valid(owner_aircraft) \
		and target != owner_aircraft \
		and FactionRelations.are_hostile(
			owner_aircraft.get_team(),
			target.get_team()
		)


func _validate_configuration(emit_warnings: bool) -> bool:
	if owner_aircraft == null \
			or not is_instance_valid(owner_aircraft) \
			or owner_aircraft.aircraft_data == null \
			or owner_aircraft.aircraft_data.role \
				!= AircraftData.AircraftRole.FIGHTER \
			or fighter_data == null \
			or gun_data == null:
		return false
	var errors := fighter_data.validate()
	if not gun_data.is_valid_configuration():
		errors.append("AircraftGunData configuration is invalid.")
	if emit_warnings:
		for error in errors:
			push_warning(
				"Fighter combat configuration '%s': %s"
				% [owner_aircraft.aircraft_data.id, error]
			)
	return errors.is_empty()


func _set_result_attacker(result: FighterShotResult) -> void:
	if result != null \
			and owner_aircraft != null \
			and is_instance_valid(owner_aircraft):
		result.attacker_instance_id = owner_aircraft.get_instance_id()
