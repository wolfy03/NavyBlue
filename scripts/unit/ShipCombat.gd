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

func set_aim_point(world_point: Vector3) -> void:
	aim_point = world_point
	has_aim_point = true
	for turret in turrets:
		if is_instance_valid(turret):
			turret.aim_at(aim_point)

func get_aim_point() -> Variant:
	return aim_point if has_aim_point else null

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

func get_primary_impact_point(gravity: float) -> Variant:
	if turrets.is_empty():
		return null
	var turret: Turret = turrets[0] as Turret
	if turret == null:
		return null
	var origin: Vector3 = turret.get_muzzle_position()
	var velocity_vector: Vector3 = turret.get_muzzle_velocity_vector()
	var effective_gravity: float = gravity * turret.ballistic_gravity_multiplier
	var a: float = -0.5 * effective_gravity
	var b: float = velocity_vector.y
	var c: float = origin.y
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return null
	var sqrt_discriminant: float = sqrt(discriminant)
	var t1: float = (-b + sqrt_discriminant) / (2.0 * a)
	var t2: float = (-b - sqrt_discriminant) / (2.0 * a)
	var t: float = maxf(t1, t2)
	if t <= 0.0:
		return null
	var point: Vector3 = origin + velocity_vector * t + Vector3(0.0, -0.5 * effective_gravity * t * t, 0.0)
	point.y = 0.035
	return point
