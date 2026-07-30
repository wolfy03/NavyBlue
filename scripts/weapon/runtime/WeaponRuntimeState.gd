extends RefCounted
class_name WeaponRuntimeState

var ammunition := -1
var cooldown_left_sec := 0.0
var enabled := true


func reset() -> void:
	cooldown_left_sec = 0.0
	enabled = true


func update(delta: float) -> void:
	cooldown_left_sec = maxf(
		cooldown_left_sec - maxf(delta, 0.0),
		0.0
	)


func has_ammunition() -> bool:
	return ammunition != 0
