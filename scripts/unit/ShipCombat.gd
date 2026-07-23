extends Node
class_name ShipCombat

var target
var aim_point := Vector3.ZERO
var has_aim_point := false
var turrets: Array = []

func setup(next_turrets: Array) -> void:
	turrets = next_turrets

func set_target(next_target) -> void:
	target = next_target


func clear_target() -> void:
	target = null
	has_aim_point = false

func set_aim_point(world_point: Vector3) -> void:
	aim_point = world_point
	has_aim_point = true

func adjust_turret_pitch(delta_degrees: float) -> void:
	for turret in turrets:
		turret.adjust_pitch(delta_degrees)

func fire_all() -> void:
	for turret in turrets:
		turret.fire()

func update_turrets(owner_ship: Node3D, use_default_aim: bool) -> void:
	if not has_aim_point and use_default_aim and owner_ship != null:
		set_aim_point(owner_ship.global_position + -owner_ship.global_transform.basis.z * 60.0)
	for turret in turrets:
		if has_aim_point:
			turret.aim_at(aim_point)


func get_primary_weapon_range_m() -> float:
	if turrets.is_empty():
		return 0.0
	return _get_turret_range_m(turrets[0])


func get_max_weapon_range_m() -> float:
	var maximum_range_m := 0.0
	for turret in turrets:
		maximum_range_m = maxf(maximum_range_m, _get_turret_range_m(turret))
	return maximum_range_m


func has_usable_weapon() -> bool:
	for turret in turrets:
		if _get_turret_range_m(turret) > 0.0:
			return true
	return false


func get_estimated_damage_per_second() -> float:
	var total_damage_per_second := 0.0
	for turret in turrets:
		if not is_instance_valid(turret):
			continue
		var data := turret.get(&"weapon_data") as WeaponData
		if data == null:
			continue
		var projectile_damage := data.damage
		if data.projectile_data != null:
			projectile_damage = data.projectile_data.damage
		var runtime_reload_sec := maxf(float(turret.get(&"reload_seconds")), 0.01)
		total_damage_per_second += maxf(projectile_damage, 0.0) / runtime_reload_sec
	return total_damage_per_second


func get_primary_impact_point(gravity: float) -> Variant:
	if turrets.is_empty():
		return null
	var turret = turrets[0]
	var origin: Vector3 = turret.get_muzzle_position()
	var velocity_vector: Vector3 = turret.get_muzzle_velocity_vector()
	var a := -0.5 * gravity
	var b := velocity_vector.y
	var c := origin.y
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return null
	var sqrt_discriminant := sqrt(discriminant)
	var t1 := (-b + sqrt_discriminant) / (2.0 * a)
	var t2 := (-b - sqrt_discriminant) / (2.0 * a)
	var t := maxf(t1, t2)
	if t <= 0.0:
		return null
	var point := origin + velocity_vector * t + Vector3(0.0, -0.5 * gravity * t * t, 0.0)
	point.y = 0.035
	return point


func _get_turret_range_m(turret) -> float:
	if not is_instance_valid(turret):
		return 0.0
	var data := turret.get(&"weapon_data") as WeaponData
	if data == null or data.range_meters <= 0.0:
		return 0.0
	return data.range_meters
