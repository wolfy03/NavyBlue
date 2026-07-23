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
	return weapon_data != null and reload_left <= 0.0 and has_aim_point


func can_fire_at(world_point: Vector3) -> bool:
	if not can_fire():
		return false
	var distance := global_position.distance_to(world_point)
	return distance >= get_minimum_range_m() and distance <= get_range_m()


func get_weapon_type() -> WeaponData.WeaponType:
	return weapon_data.weapon_type if weapon_data != null else WeaponData.WeaponType.UTILITY


func get_range_m() -> float:
	return weapon_data.range_meters if weapon_data != null else 0.0


func get_minimum_range_m() -> float:
	return weapon_data.minimum_range_meters if weapon_data != null else 0.0


func get_reload_seconds() -> float:
	return weapon_data.reload_seconds if weapon_data != null else 0.0


func get_estimated_damage() -> float:
	if weapon_data == null:
		return 0.0
	if weapon_data.projectile_data != null:
		return weapon_data.projectile_data.damage
	return weapon_data.damage


func get_estimated_dps() -> float:
	return get_estimated_damage() / maxf(get_reload_seconds(), 0.01)


func get_owner_ship() -> ShipUnit:
	return owner_ship if is_instance_valid(owner_ship) else null


func get_muzzle_position() -> Vector3:
	return global_position


func get_muzzle_velocity_vector() -> Vector3:
	return Vector3.ZERO


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
	var direction := world_point - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return true
	var ship_basis := owner_ship.global_transform.basis if owner_ship != null \
		else global_transform.basis
	var local_direction := ship_basis.inverse() * direction.normalized()
	var yaw_degrees := rad_to_deg(atan2(-local_direction.x, -local_direction.z))
	return _is_angle_inside_limits(
		yaw_degrees,
		slot_data.traverse_min_degrees,
		slot_data.traverse_max_degrees
	)


func _is_angle_inside_limits(angle: float, minimum: float, maximum: float) -> bool:
	if maximum - minimum >= 359.9:
		return true
	var normalized_angle := wrapf(angle, -180.0, 180.0)
	var normalized_min := wrapf(minimum, -180.0, 180.0)
	var normalized_max := wrapf(maximum, -180.0, 180.0)
	if normalized_min <= normalized_max:
		return normalized_angle >= normalized_min and normalized_angle <= normalized_max
	return normalized_angle >= normalized_min or normalized_angle <= normalized_max
