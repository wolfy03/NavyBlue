extends RefCounted
class_name DiveBombCommand

# A resolved player dive-bomb order: the world point the player clicked, the
# target's velocity (zero for a static ground point) and the dispersion radius
# bombs will scatter within.

var command_id := 0
var target_point := Vector3.ZERO
var target_velocity := Vector3.ZERO
var dispersion_radius_m := 0.0


func duplicate_command() -> DiveBombCommand:
	var copy := DiveBombCommand.new()
	copy.command_id = command_id
	copy.target_point = target_point
	copy.target_velocity = target_velocity
	copy.dispersion_radius_m = dispersion_radius_m
	return copy
