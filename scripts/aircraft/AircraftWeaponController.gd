extends Node
class_name AircraftWeaponController

signal weapon_released(aircraft: AircraftUnit, projectile: Node)
signal payload_release_completed(
	aircraft: AircraftUnit,
	request_id: int,
	projectile: Node3D
)
signal payload_release_failed(
	aircraft: AircraftUnit,
	request_id: int,
	reason: int
)
signal payload_release_cancelled(
	aircraft: AircraftUnit,
	request_id: int
)
signal ammunition_depleted
signal gun_burst_fired(
	aircraft: AircraftUnit,
	target: AircraftUnit,
	rounds_fired: int,
	hits: int
)

enum ReleaseFailureReason {
	NONE,
	SPAWN_FAILED,
	INVALID_CONFIGURATION,
	RELEASE_DISABLED,
	CANCELLED,
}

static var _next_payload_release_request_id := 1

var owner_aircraft: AircraftUnit
var weapon_data: AircraftWeaponData
var remaining_ammunition := 0
var release_cooldown_left := 0.0
var gun_burst_cooldown_left := 0.0

var _active_release_request_id := -1
var _pending_release_count := 0
var _pending_target_position := Vector3.ZERO
var _pending_target_velocity := Vector3.ZERO
var _last_spawned_projectile: Node3D
var _configuration_warning_emitted := false
var _depletion_emitted := false
var _release_enabled := true
var battle_services: BattleServices


func setup(
		next_owner_aircraft: AircraftUnit,
		data: AircraftWeaponData,
		next_battle_services: BattleServices = null
) -> void:
	owner_aircraft = next_owner_aircraft
	weapon_data = data
	battle_services = next_battle_services
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
	_clear_active_release_request()
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
	if _active_release_request_id < 0 \
			or _pending_release_count <= 0 \
			or release_cooldown_left > 0.0:
		return
	_process_payload_release()


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
		and _active_release_request_id < 0 \
		and _pending_release_count <= 0


func can_retry_payload_release() -> bool:
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
		and remaining_ammunition > 0


func is_release_enabled() -> bool:
	return _release_enabled


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
		weapon_data.gun_data.get_burst_duration_sec()
			+ weapon_data.gun_data.burst_cooldown_sec,
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
	if battle_services != null:
		battle_services.events.emit_fighter_gun_burst(
			owner_aircraft,
			target,
			result.rounds_fired,
			result.hit_count,
			result.hit_probability
		)
		if result.total_damage > 0.0:
			battle_services.events.emit_aircraft_gun_hit(
				owner_aircraft,
				target,
				result.total_damage
			)


func request_release(
		target_position: Vector3,
		target_velocity: Vector3 = Vector3.ZERO
) -> int:
	if not can_release():
		return -1
	var request_id := _allocate_release_request_id()
	_active_release_request_id = request_id
	_pending_target_position = target_position
	_pending_target_velocity = target_velocity
	_pending_release_count = mini(
		_get_projectiles_for_release(),
		remaining_ammunition
	)
	_last_spawned_projectile = null
	if _pending_release_count <= 0:
		_emit_release_failed(ReleaseFailureReason.INVALID_CONFIGURATION)
		return -1
	return request_id


func release(
		target_position: Vector3,
		target_velocity: Vector3 = Vector3.ZERO
) -> bool:
	var ammunition_before := remaining_ammunition
	var request_id := request_release(target_position, target_velocity)
	if request_id < 0:
		return false
	_process_payload_release()
	return remaining_ammunition < ammunition_before


func is_release_in_progress() -> bool:
	return _active_release_request_id >= 0 \
		or _pending_release_count > 0


func get_active_release_request_id() -> int:
	return _active_release_request_id


func disable_weapon_release() -> void:
	if _active_release_request_id >= 0:
		cancel_release_request(_active_release_request_id)
	_release_enabled = false
	gun_burst_cooldown_left = 0.0


func cancel_pending_release() -> void:
	if _active_release_request_id >= 0:
		cancel_release_request(_active_release_request_id)
	else:
		_clear_active_release_request()
	release_cooldown_left = 0.0


func cancel_release_request(request_id: int) -> bool:
	if request_id < 0 or request_id != _active_release_request_id:
		return false
	var cancelled_request_id := _active_release_request_id
	_clear_active_release_request()
	payload_release_cancelled.emit(
		owner_aircraft,
		cancelled_request_id
	)
	return true


func _process_payload_release() -> void:
	if _active_release_request_id < 0 or _pending_release_count <= 0:
		return
	var projectile := _spawn_projectile(
		_pending_target_position,
		_pending_target_velocity
	)
	if projectile == null:
		_emit_release_failed(ReleaseFailureReason.SPAWN_FAILED)
		return
	_last_spawned_projectile = projectile
	_pending_release_count -= 1
	release_cooldown_left = maxf(
		weapon_data.release_interval_sec,
		0.0
	)
	if _pending_release_count <= 0:
		var completed_request_id := _active_release_request_id
		var completed_projectile := _last_spawned_projectile
		_clear_active_release_request()
		payload_release_completed.emit(
			owner_aircraft,
			completed_request_id,
			completed_projectile
		)


func _get_projectiles_for_release() -> int:
	if weapon_data == null:
		return 0
	if weapon_data.release_mode == AircraftWeaponData.ReleaseMode.SINGLE:
		return 1
	return maxi(weapon_data.projectiles_per_release, 1)


func _spawn_projectile(
		target_position: Vector3,
		_target_velocity: Vector3
) -> Node3D:
	if weapon_data == null or weapon_data.projectile_scene == null \
			or weapon_data.projectile_data == null:
		_warn_invalid_configuration_once()
		return null
	var projectile_parent := _resolve_projectile_parent()
	if projectile_parent == null:
		return null
	if battle_services == null:
		push_error("AircraftWeaponController requires BattleServices.")
		return null
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
	var creation := battle_services.projectile_factory.create_result(
		weapon_data.projectile_scene,
		projectile_parent,
		weapon_data.projectile_data,
		context
	)
	var projectile := creation.projectile
	if projectile == null:
		return null
	remaining_ammunition = maxi(remaining_ammunition - 1, 0)
	weapon_released.emit(owner_aircraft, projectile)
	if battle_services != null:
		battle_services.events.emit_aircraft_released_payload(
			owner_aircraft,
			projectile
		)
	if remaining_ammunition <= 0 and not _depletion_emitted:
		_depletion_emitted = true
		ammunition_depleted.emit()
	return projectile


func _emit_release_failed(reason: ReleaseFailureReason) -> void:
	if _active_release_request_id < 0:
		return
	var failed_request_id := _active_release_request_id
	_clear_active_release_request()
	payload_release_failed.emit(
		owner_aircraft,
		failed_request_id,
		int(reason)
	)


func _clear_active_release_request() -> void:
	_active_release_request_id = -1
	_pending_release_count = 0
	_pending_target_position = Vector3.ZERO
	_pending_target_velocity = Vector3.ZERO
	_last_spawned_projectile = null


func _allocate_release_request_id() -> int:
	var request_id := _next_payload_release_request_id
	_next_payload_release_request_id += 1
	if _next_payload_release_request_id <= 0:
		_next_payload_release_request_id = 1
	return request_id


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
