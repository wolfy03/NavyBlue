extends RefCounted
class_name ProjectileImpactResult

enum SurfaceType {
	WATER,
	SHIP,
	TERRAIN,
	UNKNOWN,
}

var projectile: Node3D
var surface_type: SurfaceType = SurfaceType.UNKNOWN
var hit_position := Vector3.ZERO
var hit_normal := Vector3.UP
var incoming_velocity := Vector3.ZERO
var impact_strength := 1.0
var target: Node3D
var damage_result: DamageResult
