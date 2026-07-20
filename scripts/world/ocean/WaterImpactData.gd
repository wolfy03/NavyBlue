extends RefCounted
class_name WaterImpactData

var world_position: Vector3 = Vector3.ZERO
var surface_normal: Vector3 = Vector3.UP
var impact_velocity: Vector3 = Vector3.ZERO
var impact_strength: float = 1.0
var impact_time: float = 0.0
var projectile_reference: WeakRef
var projectile_id: int = 0


func setup(
		position: Vector3,
		normal: Vector3,
		velocity: Vector3,
		strength: float,
		time_seconds: float,
		projectile: Object = null
) -> void:
	world_position = position
	surface_normal = normal.normalized()
	if surface_normal.dot(Vector3.UP) < 0.0:
		surface_normal = -surface_normal
	impact_velocity = velocity
	impact_strength = maxf(strength, 0.0)
	impact_time = maxf(time_seconds, 0.0)
	if projectile != null:
		projectile_reference = weakref(projectile)
		projectile_id = projectile.get_instance_id()
