extends Node3D
class_name WeaponMount

signal fired(projectile: Node)
signal reload_changed(current: float, maximum: float)

var weapon_data: WeaponData
var slot_data: ShipWeaponSlotData
var owner_ship: ShipUnit
var owner_team: StringName = &"neutral"
var aim_point := Vector3.ZERO
var has_aim_point := false
var reload_left := 0.0
var base_local_yaw_radians := 0.0
var runtime_stats := WeaponRuntimeStats.new()


func setup(
		data: WeaponData,
		slot: ShipWeaponSlotData,
		ship: ShipUnit,
		team: StringName
) -> void:
	weapon_data = data
	slot_data = slot
	owner_ship = ship
	owner_team = team
	reload_left = 0.0
	base_local_yaw_radians = rotation.y
	runtime_stats = WeaponRuntimeStats.new()


func set_runtime_stats(stats: WeaponRuntimeStats) -> void:
	runtime_stats = stats.duplicate_stats() \
		if stats != null else WeaponRuntimeStats.new()


func get_runtime_stats() -> WeaponRuntimeStats:
	return runtime_stats


func _physics_process(delta: float) -> void:
	var previous_reload := reload_left
	reload_left = maxf(0.0, reload_left - delta)
	if not is_equal_approx(previous_reload, reload_left):
		reload_changed.emit(reload_left, get_reload_seconds())


func aim_at(world_point: Vector3) -> void:
	aim_point = world_point
	has_aim_point = true


func clear_aim() -> void:
	has_aim_point = false


func fire() -> bool:
	push_warning("WeaponMount.fire() must be overridden by a concrete mount.")
	return false


func can_fire() -> bool:
	return can_fire_at(aim_point)


func can_fire_at(world_point: Vector3) -> bool:
	return get_fire_readiness_at(world_point) \
		== WeaponFireReadiness.State.READY


func get_fire_readiness_at(
		world_point: Vector3
) -> WeaponFireReadiness.State:
	if weapon_data == null:
		return WeaponFireReadiness.State.NO_WEAPON_DATA
	if not has_aim_point:
		return WeaponFireReadiness.State.NO_AIM_POINT
	if not world_point.is_finite():
		return WeaponFireReadiness.State.INVALID_TARGET
	if reload_left > 0.0:
		return WeaponFireReadiness.State.RELOADING
	var distance := get_distance_to_world_point(world_point)
	if distance < get_minimum_range_m():
		return WeaponFireReadiness.State.INSIDE_MINIMUM_RANGE
	if distance > get_range_m():
		return WeaponFireReadiness.State.OUT_OF_RANGE
	if not _is_inside_traverse_arc(world_point):
		return WeaponFireReadiness.State.OUTSIDE_TRAVERSE
	if not _has_projectile_available():
		return WeaponFireReadiness.State.NO_PROJECTILE_SCENE
	return WeaponFireReadiness.State.READY


func update_traverse_toward(
		world_point: Vector3,
		speed_degrees_per_second: float,
		delta: float
) -> void:
	if delta <= 0.0 or speed_degrees_per_second <= 0.0:
		return
	var requested_relative_yaw: Variant = _get_requested_relative_yaw_degrees(
		world_point
	)
	if requested_relative_yaw == null:
		return
	var clamped_relative_yaw := _clamp_angle_to_traverse_limits(
		float(requested_relative_yaw)
	)
	var desired_local_yaw := base_local_yaw_radians \
		+ deg_to_rad(clamped_relative_yaw)
	rotation.y = wrapf(
		rotate_toward(
			rotation.y,
			desired_local_yaw,
			deg_to_rad(speed_degrees_per_second) * delta
		),
		-PI,
		PI
	)


func get_weapon_type() -> WeaponTypes.Type:
	return weapon_data.weapon_type if weapon_data != null else WeaponTypes.Type.UTILITY


func get_range_m() -> float:
	if weapon_data == null:
		return 0.0
	return weapon_data.range_meters * maxf(runtime_stats.range_multiplier, 0.0)


func get_minimum_range_m() -> float:
	return weapon_data.minimum_range_meters if weapon_data != null else 0.0


func get_distance_to_world_point(world_point: Vector3) -> float:
	return global_position.distance_to(world_point)


func get_reload_seconds() -> float:
	if weapon_data == null:
		return 0.0
	return weapon_data.reload_seconds * maxf(
		runtime_stats.reload_multiplier,
		0.01
	)


func get_projectile_damage() -> float:
	return _get_base_projectile_damage() * maxf(
		runtime_stats.damage_multiplier,
		0.0
	)


func get_salvo_projectile_count() -> int:
	return maxi(1, 1 + runtime_stats.projectile_count_bonus)


func get_salvo_damage() -> float:
	return get_projectile_damage() * float(get_salvo_projectile_count())


func get_sustained_dps() -> float:
	return get_salvo_damage() / maxf(get_reload_seconds(), 0.01)


func get_ready_salvo_damage() -> float:
	return get_salvo_damage() if reload_left <= 0.0 else 0.0


func get_estimated_damage() -> float:
	return get_salvo_damage()


func get_estimated_dps() -> float:
	return get_sustained_dps()


func get_owner_ship() -> ShipUnit:
	return owner_ship if is_instance_valid(owner_ship) else null


func get_muzzle_position() -> Vector3:
	return global_position


func get_muzzle_velocity_vector() -> Vector3:
	return Vector3.ZERO


func get_modified_projectile_speed(base_speed: float) -> float:
	return base_speed * maxf(runtime_stats.projectile_speed_multiplier, 0.0)


func get_modified_traverse_speed(base_speed: float) -> float:
	return base_speed * maxf(runtime_stats.traverse_speed_multiplier, 0.0)


func get_modified_flooding_chance(base_chance: float) -> float:
	return clampf(
		base_chance + runtime_stats.flooding_chance_bonus,
		0.0,
		1.0
	)


func adjust_pitch(_delta_degrees: float) -> void:
	return


func _spawn_projectile(scene: PackedScene) -> Node:
	var parent := _get_projectile_parent()
	if scene == null or parent == null:
		return null
	if has_node("/root/ObjectPool"):
		var pooled: Node = get_node("/root/ObjectPool").spawn(scene, parent)
		if pooled != null:
			return pooled
	var projectile := scene.instantiate()
	if projectile != null:
		parent.add_child(projectile)
	return projectile


func _get_projectile_parent() -> Node:
	if get_tree() == null:
		return null
	var ancestor := get_parent()
	while ancestor != null:
		var projectiles := ancestor.get_node_or_null("Projectiles")
		if projectiles != null:
			return projectiles
		ancestor = ancestor.get_parent()
	var current_scene := get_tree().current_scene
	if current_scene != null:
		var projectiles := current_scene.get_node_or_null("Projectiles")
		return projectiles if projectiles != null else current_scene
	return get_tree().root


func _is_inside_traverse_arc(world_point: Vector3) -> bool:
	if slot_data == null:
		return true
	var relative_yaw: Variant = _get_requested_relative_yaw_degrees(world_point)
	if relative_yaw == null:
		return true
	return _is_angle_inside_limits(
		float(relative_yaw),
		slot_data.traverse_min_degrees,
		slot_data.traverse_max_degrees
	)


func _get_requested_relative_yaw_degrees(world_point: Vector3) -> Variant:
	var direction := world_point - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return null
	var reference_basis := global_transform.basis
	if owner_ship != null and is_instance_valid(owner_ship):
		reference_basis = owner_ship.global_transform.basis
	else:
		var parent_3d := get_parent_node_3d()
		if parent_3d != null:
			reference_basis = parent_3d.global_transform.basis
	var local_direction := reference_basis.inverse() * direction.normalized()
	var requested_ship_yaw := rad_to_deg(
		atan2(-local_direction.x, -local_direction.z)
	)
	return wrapf(
		requested_ship_yaw - rad_to_deg(base_local_yaw_radians),
		-180.0,
		180.0
	)


func _clamp_angle_to_traverse_limits(relative_yaw: float) -> float:
	if slot_data == null or _has_full_traverse():
		return wrapf(relative_yaw, -180.0, 180.0)
	var minimum := wrapf(slot_data.traverse_min_degrees, -180.0, 180.0)
	var maximum := wrapf(slot_data.traverse_max_degrees, -180.0, 180.0)
	var normalized_yaw := wrapf(relative_yaw, -180.0, 180.0)
	if _is_angle_inside_limits(normalized_yaw, minimum, maximum):
		return normalized_yaw
	var distance_to_minimum := absf(
		wrapf(minimum - normalized_yaw, -180.0, 180.0)
	)
	var distance_to_maximum := absf(
		wrapf(maximum - normalized_yaw, -180.0, 180.0)
	)
	return minimum if distance_to_minimum <= distance_to_maximum else maximum


func _is_angle_inside_limits(angle: float, minimum: float, maximum: float) -> bool:
	if absf(maximum - minimum) >= 359.9:
		return true
	var normalized_angle := wrapf(angle, -180.0, 180.0)
	var normalized_min := wrapf(minimum, -180.0, 180.0)
	var normalized_max := wrapf(maximum, -180.0, 180.0)
	if normalized_min <= normalized_max:
		return normalized_angle >= normalized_min and normalized_angle <= normalized_max
	return normalized_angle >= normalized_min or normalized_angle <= normalized_max


func _has_full_traverse() -> bool:
	return slot_data == null \
		or absf(
			slot_data.traverse_max_degrees
			- slot_data.traverse_min_degrees
		) >= 359.9


func _has_projectile_available() -> bool:
	return weapon_data != null and weapon_data.projectile_scene != null


func _get_base_projectile_damage() -> float:
	if weapon_data == null:
		return 0.0
	if weapon_data.projectile_data != null:
		return weapon_data.projectile_data.damage
	return weapon_data.damage


func _is_aim_aligned(
		world_point: Vector3,
		tolerance_degrees: float
) -> bool:
	var desired_direction := world_point - global_position
	desired_direction.y = 0.0
	var mount_forward := -global_transform.basis.z
	mount_forward.y = 0.0
	if desired_direction.length_squared() < 0.01 \
			or mount_forward.length_squared() < 0.01:
		return false
	return rad_to_deg(
		mount_forward.normalized().angle_to(desired_direction.normalized())
	) <= maxf(tolerance_degrees, 0.0)
