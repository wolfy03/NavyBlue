extends RefCounted
class_name ProjectileRuntimeState

var active := false
var elapsed_sec := 0.0
var velocity := Vector3.ZERO
var impact_resolved := false
var creation_ownership := ProjectileCreationOwnership.Type.NONE


func reset() -> void:
	active = false
	elapsed_sec = 0.0
	velocity = Vector3.ZERO
	impact_resolved = false
	creation_ownership = ProjectileCreationOwnership.Type.NONE
