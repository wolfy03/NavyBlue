extends RefCounted
class_name ShellCollisionResult

enum Type {
	NONE,
	SHIP,
	WATER,
}

var hit: bool = false
var type: Type = Type.NONE
var ratio: float = 1.0
var position: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.UP
var collider: Object
var target_ship: Node3D
