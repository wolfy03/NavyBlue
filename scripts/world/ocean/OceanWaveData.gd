@tool
extends Resource
class_name OceanWaveData

const SAFE_DIRECTION := Vector2.RIGHT
const MIN_DIRECTION_LENGTH_SQUARED := 0.000001

@export var direction: Vector2 = SAFE_DIRECTION:
	set(value):
		direction = value
		emit_changed()

@export_range(0.0, 10.0, 0.01, "or_greater") var amplitude: float = 0.5:
	set(value):
		amplitude = maxf(value, 0.0)
		emit_changed()

@export_range(0.0, 2.0, 0.001, "or_greater") var frequency: float = 0.05:
	set(value):
		frequency = maxf(value, 0.0)
		emit_changed()

@export_range(-20.0, 20.0, 0.01, "or_less", "or_greater") var speed: float = 1.0:
	set(value):
		speed = value
		emit_changed()

@export var phase_offset: float = 0.0:
	set(value):
		phase_offset = value
		emit_changed()


func get_normalized_direction() -> Vector2:
	if direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return SAFE_DIRECTION
	return direction.normalized()


func get_phase(world_xz: Vector2, time_seconds: float) -> float:
	var safe_direction := get_normalized_direction()
	return safe_direction.dot(world_xz) * frequency + time_seconds * speed + phase_offset


func sample_height(world_xz: Vector2, time_seconds: float) -> float:
	return sin(get_phase(world_xz, time_seconds)) * amplitude
