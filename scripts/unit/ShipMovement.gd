extends Node
class_name ShipMovement

func compute_velocity(transform: Transform3D, engine_output: float, forward_speed: float, reverse_speed: float) -> Vector3:
	var speed_limit := forward_speed if engine_output >= 0.0 else reverse_speed
	return -transform.basis.z.normalized() * engine_output * speed_limit

