extends RefCounted
class_name WaterSurfaceHit

var hit: bool = false
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var interpolation_ratio: float = 0.0


static func miss() -> RefCounted:
	return new()


static func from_hit(hit_position: Vector3, hit_normal: Vector3, ratio: float) -> RefCounted:
	var result := new()
	result.hit = true
	result.position = hit_position
	result.normal = hit_normal.normalized()
	if result.normal.dot(Vector3.UP) < 0.0:
		result.normal = -result.normal
	result.interpolation_ratio = clampf(ratio, 0.0, 1.0)
	return result
