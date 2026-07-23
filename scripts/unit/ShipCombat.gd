extends Node
class_name ShipCombat

var target
var aim_point := Vector3.ZERO
var has_aim_point := false
var weapon_mounts: Array[WeaponMount] = []
var turrets: Array = []
var owner_ship: ShipUnit


func setup(next_owner_ship: ShipUnit, next_weapon_mounts: Array) -> void:
	owner_ship = next_owner_ship
	weapon_mounts.clear()
	for mount_value in next_weapon_mounts:
		var mount := mount_value as WeaponMount
		if mount != null:
			weapon_mounts.append(mount)
	turrets.assign(get_weapons_by_type(WeaponData.WeaponType.CANNON))


func set_target(next_target) -> void:
	target = next_target


func clear_target() -> void:
	target = null
	has_aim_point = false
	for mount in weapon_mounts:
		if is_instance_valid(mount):
			mount.clear_aim()


func set_aim_point(world_point: Vector3) -> void:
	aim_point = world_point
	has_aim_point = true
	for mount in weapon_mounts:
		if is_instance_valid(mount):
			mount.aim_at(world_point)


func adjust_turret_pitch(delta_degrees: float) -> void:
	for mount in get_weapons_by_type(WeaponData.WeaponType.CANNON):
		mount.adjust_pitch(delta_degrees)


func fire_weapon_type(weapon_type: WeaponData.WeaponType) -> int:
	var fired_count := 0
	for mount in weapon_mounts:
		if not is_instance_valid(mount) or mount.get_weapon_type() != weapon_type:
			continue
		if mount.fire():
			fired_count += 1
	return fired_count


func fire_cannons() -> int:
	return fire_weapon_type(WeaponData.WeaponType.CANNON)


func fire_torpedoes() -> int:
	return fire_weapon_type(WeaponData.WeaponType.TORPEDO)


func fire_torpedoes_at(
		target_ship: ShipUnit,
		bounds: BattlefieldBounds = null,
		minimum_hit_probability: float = 0.35
) -> int:
	if owner_ship == null or target_ship == null or not target_ship.is_alive():
		return 0
	var fired_count := 0
	for mount in get_weapons_by_type(WeaponData.WeaponType.TORPEDO):
		var data := mount.weapon_data.projectile_data as TorpedoProjectileData
		if data == null:
			continue
		var lead_point := calculate_torpedo_lead_point(
			mount.global_position,
			target_ship,
			data.max_speed_mps
		)
		lead_point.y = owner_ship.global_position.y
		if bounds != null and not bounds.is_inside_bounds(lead_point):
			continue
		if _estimate_torpedo_hit_probability(
			mount.global_position,
			target_ship,
			data.max_speed_mps
		) < minimum_hit_probability:
			continue
		mount.aim_at(lead_point)
		if mount.fire():
			fired_count += 1
	return fired_count


func fire_all() -> void:
	fire_cannons()


func update_weapon_mounts(next_owner_ship: Node3D, use_default_aim: bool) -> void:
	if not has_aim_point and use_default_aim and next_owner_ship != null:
		set_aim_point(
			next_owner_ship.global_position
			+ -next_owner_ship.global_transform.basis.z * 60.0
		)
	if not has_aim_point:
		return
	for mount in weapon_mounts:
		if is_instance_valid(mount):
			mount.aim_at(aim_point)


func update_turrets(next_owner_ship: Node3D, use_default_aim: bool) -> void:
	update_weapon_mounts(next_owner_ship, use_default_aim)


func get_weapons_by_type(
		weapon_type: WeaponData.WeaponType
) -> Array[WeaponMount]:
	var result: Array[WeaponMount] = []
	for mount in weapon_mounts:
		if is_instance_valid(mount) and mount.get_weapon_type() == weapon_type:
			result.append(mount)
	return result


func can_fire_weapon_type_at(
		weapon_type: WeaponData.WeaponType,
		world_point: Vector3
) -> bool:
	for mount in weapon_mounts:
		if is_instance_valid(mount) \
				and mount.get_weapon_type() == weapon_type \
				and mount.can_fire_at(world_point):
			return true
	return false


func get_primary_weapon_range_m() -> float:
	var cannons := get_weapons_by_type(WeaponData.WeaponType.CANNON)
	if not cannons.is_empty():
		return cannons[0].get_range_m()
	return weapon_mounts[0].get_range_m() if not weapon_mounts.is_empty() else 0.0


func get_max_weapon_range_m(type_filter: Variant = null) -> float:
	var maximum_range_m := 0.0
	for mount in weapon_mounts:
		if not is_instance_valid(mount):
			continue
		if type_filter != null and mount.get_weapon_type() != int(type_filter):
			continue
		maximum_range_m = maxf(maximum_range_m, mount.get_range_m())
	return maximum_range_m


func has_usable_weapon() -> bool:
	for mount in weapon_mounts:
		if is_instance_valid(mount) and mount.get_range_m() > 0.0:
			return true
	return false


func is_target_in_range(target_ship: ShipUnit) -> bool:
	if owner_ship == null or target_ship == null \
			or not is_instance_valid(target_ship) or not target_ship.is_alive():
		return false
	var range_m := get_max_weapon_range_m()
	return range_m > 0.0 \
		and owner_ship.global_position.distance_squared_to(target_ship.global_position) \
			<= range_m * range_m


func get_estimated_damage_per_second() -> float:
	var total_damage_per_second := 0.0
	for mount in weapon_mounts:
		if is_instance_valid(mount):
			total_damage_per_second += mount.get_estimated_dps()
	return total_damage_per_second


func estimate_available_turret_ratio(target_direction: Vector3) -> float:
	var cannons := get_weapons_by_type(WeaponData.WeaponType.CANNON)
	if cannons.is_empty() or target_direction.length_squared() < 0.01:
		return 0.0
	if owner_ship == null:
		return 1.0
	target_direction.y = 0.0
	var forward := -owner_ship.global_transform.basis.z
	forward.y = 0.0
	var angle_deg := rad_to_deg(absf(forward.angle_to(target_direction.normalized())))
	var broadside_angle_deg := owner_ship.ai.get_preferred_broadside_angle_deg() \
		if owner_ship.ai != null else 70.0
	if broadside_angle_deg <= 0.0:
		return 0.5
	return clampf(
		1.0 - absf(angle_deg - broadside_angle_deg) / 100.0,
		0.25,
		1.0
	)


func get_primary_impact_point(gravity: float) -> Variant:
	var cannons := get_weapons_by_type(WeaponData.WeaponType.CANNON)
	if cannons.is_empty():
		return null
	var cannon := cannons[0]
	var origin := cannon.get_muzzle_position()
	var velocity_vector := cannon.get_muzzle_velocity_vector()
	var a := -0.5 * gravity
	var b := velocity_vector.y
	var c := origin.y
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return null
	var sqrt_discriminant := sqrt(discriminant)
	var t1 := (-b + sqrt_discriminant) / (2.0 * a)
	var t2 := (-b - sqrt_discriminant) / (2.0 * a)
	var time := maxf(t1, t2)
	if time <= 0.0:
		return null
	var point := origin + velocity_vector * time \
		+ Vector3(0.0, -0.5 * gravity * time * time, 0.0)
	point.y = 0.035
	return point


func calculate_torpedo_lead_point(
		launcher_position: Vector3,
		target_ship: ShipUnit,
		torpedo_speed_mps: float
) -> Vector3:
	if target_ship == null:
		return launcher_position
	var distance := launcher_position.distance_to(target_ship.global_position)
	var travel_time := distance / maxf(torpedo_speed_mps, 0.01)
	return target_ship.global_position + target_ship.velocity * travel_time


func _estimate_torpedo_hit_probability(
		launcher_position: Vector3,
		target_ship: ShipUnit,
		torpedo_speed_mps: float
) -> float:
	var distance := launcher_position.distance_to(target_ship.global_position)
	var travel_time := distance / maxf(torpedo_speed_mps, 0.01)
	var target_speed := target_ship.velocity.length()
	var maneuver_penalty := clampf(
		target_speed / maxf(torpedo_speed_mps, 0.01),
		0.0,
		1.0
	) * 0.3
	var time_penalty := clampf(travel_time / 120.0, 0.0, 0.45)
	return clampf(0.92 - maneuver_penalty - time_penalty, 0.05, 0.95)
