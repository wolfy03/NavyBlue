extends RefCounted
class_name ProjectileCreationResult

enum ErrorCode {
	NONE,
	INVALID_ARGUMENT,
	POOL_ACQUIRE_FAILED,
	INVALID_PROJECTILE_ROOT,
	CONFIGURE_FAILED,
	LAUNCH_FAILED,
}

var projectile: Node3D
var used_pool := false
var ownership := ProjectileCreationOwnership.Type.NONE
var error := ErrorCode.NONE


func succeeded() -> bool:
	return projectile != null and error == ErrorCode.NONE
