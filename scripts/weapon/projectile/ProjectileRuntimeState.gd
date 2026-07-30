extends RefCounted
class_name ProjectileRuntimeState

var active := false
var elapsed_sec := 0.0
var velocity := Vector3.ZERO
var impact_resolved := false


func reset() -> void:
	active = false
	elapsed_sec = 0.0
	velocity = Vector3.ZERO
	impact_resolved = false
