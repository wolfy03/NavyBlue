extends Node
class_name AircraftWeaponController

signal weapon_released(aircraft: AircraftUnit, projectile: Node)
signal ammunition_depleted
signal gun_burst_fired(
	aircraft: AircraftUnit,
	target: AircraftUnit,
	rounds_fired: int,
	hits: int
)

var owner_aircraft: AircraftUnit
var weapon_data: AircraftWeaponData
var remaining_ammunition := 0
var release_cooldown_left := 0.0
var gun_burst_cooldown_left := 0.0

var _pending_release_count := 0
var _pending_target_position := Vector3.ZERO
var _pending_target_velocity := Vector3.ZERO
var _configuration_warning_emitted := false
var _depletion_emitted := false
var _release_enabled := true


func setup(
		next_owner_aircraft: AircraftUnit,
		data: AircraftWeaponData
) -> void:
	owner_aircraft = next_owner_aircraft
	weapon_data = data
	_configuration_warning_emitted = false
	if weapon_data != null and not weapon_data.is_valid_configuration():
		_warn_invalid_configuration_once()
	reset_for_sortie()


func reset_for_sortie() -> void:
	_release_enabled = true
	remaining_ammunition = maxi(
		weapon_data.ammunition_per_sortie if weapon_data != null else 0,
		0
	)
	release_cooldown_left = 0.0
	gun_burst_cooldown_left = 0.0
	_pending_release_count = 0
	_pending_target_position = Vector3.ZERO
	_pending_target_velocity = Vector3.ZERO
	_depletion_emitted = false


func update_weapon(delta: float) -> void:
	release_cooldown_left = maxf(
		0.0,
		release_cooldown_left - maxf(delta, 0.0)
	)
	gun_burst_cooldown_left = maxf(
		0.0,
		gun_burst_cooldown_left - maxf(delta, 0.0)
	)
	if _pending_release_count <= 0 or release_cooldown_left > 0.0:
		return
	if not _spawn_projectile(
		_pending_target_position,
		_pending_target_velocity
	):
		_pending_release_count = 0
		return
	_pending_release_count -= 1
	release_cooldown_left = maxf(weapon_data.release_interval_sec, 0.0)


func can_release() -> bool:
	return _release_enabled \
		and owner_aircraft != null \
		and is_instance_valid(owner_aircraft) \
		and owner_aircraft.is_alive() \
		and weapon_data != null \
		and weapon_data.weapon_type \
			in [
				AircraftWeaponData.WeaponType.BOMB,
				AircraftWeaponData.WeaponType.TORPEDO,
			] \
		and weapon_data.is_valid_configuration() \
		and remaining_ammunition > 0 \
		and release_cooldown_left <= 0.0 \
		and _pending_release_count <= 0


func has_ammunition() -> bool:
	return remaining_ammunition > 0


func get_remaining_ammunition() -> int:
	return remaining_ammunition


func can_fire_gun_burst() -> bool:
	return _release_enabled \
		and owner_aircraft != null \
		and is_instance_valid(owner_aircraft) \
		and owner_aircraft.is_alive() \
		and weapon_data != null \
		and weapon_data.weapon_type \
			== AircraftWeaponData.WeaponType.AIR_TO_AIR_GUN \
		and weapon_data.gun_data != null \
		and weapon_data.gun_data.is_valid_configuration() \
		and remaining_ammunition > 0 \
		and gun_burst_cooldown_left <= 0.0


func consume_gun_rounds(requested_rounds: int) -> int:
	if not can_fire_gun_burst() or requested_rounds <= 0:
		return 0
	var consumed := mini(requested_rounds, remaining_ammunition)
	remaining_ammunition -= consumed
	if remaining_ammunition <= 0 and not _depletion_emitted:
		_depletion_emitted = true
		ammunition_depleted.emit()
	return consumed


func begin_gun_burst_cooldown() -> void:
	if weapon_data == null or weapon_data.gun_data == null:
		return
	gun_burst_cooldown_left = maxf(
		weapon_data.gun_data.burst_cooldown_sec,
		0.0
	)


func emit_gun_burst_result(
		target: AircraftUnit,
		result: FighterShotResult
) -> void:
	if result == null or owner_aircraft == null:
		return
	gun_burst_fired.emit(
		owner_aircraft,
		target,
		result.rounds_fired,
		result.hit_count
	)
	if has_node("/root/EventBus"):
		var event_bus := get_node("/root/EventBus")
		event_bus.fighter_gun_burst_fired.emit(
			owner_aircraft,
			target,
			result.rounds_fired,
			result.hit_count,
			result.hit_probability
		)
		if result.total_damage > 0.0:
			event_bus.aircraft_gun_hit.emit(
				owner_aircraft,
				target,
				result.total_damage
			)


func is_release_in_progress() -> bool:
	return _pending_release_count > 0


func disable_weapon_release() -> void:
	_release_enabled = false
	gun_burst_cooldown_left = 0.0
	_pending_release_count = 0
	_pending_target_position = Vector3.ZERO
	_pending_target_velocity = Vector3.ZERO


func release(
		target_position: Vector3,
		target_velocity: Vector3 = Vector3.ZERO
) -> bool:
	if not can_release():
		return false
	_pending_target_position = target_position
	_pending_target_velocity = target_velocity
	_pending_release_count = mini(
		_get_projectiles_for_release(),
		remaining_ammunition
	)
	if _pending_release_count <= 0:
		return false
	if not _spawn_projectile(target_position, target_velocity):
		_pending_release_count = 0
		return false
	_pending_release_count -= 1
	release_cooldown_left = maxf(weapon_data.release_interval_sec, 0.0)
	return true


func _get_projectiles_for_release() -> int:
	if weapon_data == null:
		return 0
	if weapon_data.release_mode == AircraftWeaponData.ReleaseMode.SINGLE:
		return 1
	return maxi(weapon_data.projectiles_per_release, 1)


func _spawn_projectile(
		target_position: Vector3,
		_target_velocity: Vector3
) -> bool:
	if weapon_data == null or weapon_data.projectile_scene == null \
			or weapon_data.projectile_data == null:
		_warn_invalid_configuration_once()
		return false
	var projectile_parent := _resolve_projectile_parent()
	if projectile_parent == null:
		return false
	var projectile: Node
	if has_node("/root/ObjectPool"):
		projectile = get_node("/root/ObjectPool").spawn(
			weapon_data.projectile_scene,
			projectile_parent
		)
	if projectile == null:
		projectile = weapon_data.projectile_scene.instantiate()
		if projectile != null:
			projectile_parent.add_child(projectile)
	if projectile == null:
		return false
	if not projectile.has_method(&"setup_projectile_data") \
			or not projectile.has_method(&"launch_with_context"):
		push_warning(
			"Aircraft weapon projectile does not implement the projectile "
			+ "setup and launch contract: %s" % weapon_data.id
		)
		if projectile.has_method(&"despawn"):
			projectile.call(&"despawn")
		else:
			projectile.queue_free()
		return false

	projectile.call(&"setup_projectile_data", weapon_data.projectile_data)
	var context := ProjectileLaunchContext.new()
	context.source_actor = owner_aircraft
	context.source_team = owner_aircraft.team
	context.source_weapon_id = StringName(weapon_data.id)
	context.source_projectile_data = weapon_data.projectile_data
	context.initial_transform = owner_aircraft.global_transform
	context.initial_transform.origin += Vector3.DOWN * 2.0
	context.initial_velocity = owner_aircraft.get_world_velocity()
	context.initial_velocity.y = minf(
		context.initial_velocity.y,
		-maxf(weapon_data.downward_release_speed_mps, 0.0)
	)
	context.aim_point = target_position
	projectile.call(&"launch_with_context", context)
	remaining_ammunition = maxi(remaining_ammunition - 1, 0)
	weapon_released.emit(owner_aircraft, projectile)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").aircraft_weapon_released.emit(
			owner_aircraft,
			projectile
		)
	if remaining_ammunition <= 0 and not _depletion_emitted:
		_depletion_emitted = true
		ammunition_depleted.emit()
	return true


func _resolve_projectile_parent() -> Node:
	if get_tree() == null:
		return null
	var grouped_root := get_tree().get_first_node_in_group(&"projectile_root")
	if grouped_root != null:
		return grouped_root
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	var named_root := current_scene.get_node_or_null("Projectiles")
	return named_root if named_root != null else current_scene


func _warn_invalid_configuration_once() -> void:
	if _configuration_warning_emitted:
		return
	_configuration_warning_emitted = true
	push_warning(
		"Aircraft weapon configuration is invalid: %s"
		% (weapon_data.id if weapon_data != null else "null")
	)
