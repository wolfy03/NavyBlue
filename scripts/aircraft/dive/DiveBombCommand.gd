extends RefCounted
class_name DiveBombCommand

# A resolved player dive-bomb order: the world point the player clicked, the
# ship that was clicked directly (if any), the target's velocity (zero for a
# static ground point) and the dispersion radius bombs will scatter within.

var command_id := 0
var target_point := Vector3.ZERO
var target_velocity := Vector3.ZERO
var dispersion_radius_m := 0.0
## The ship the player clicked directly. Weak: the command never keeps a
## dead ship alive. Null for ocean/position clicks.
var target_ship_ref: WeakRef


func get_target_ship() -> ShipUnit:
	if target_ship_ref == null:
		return null
	var value: Variant = target_ship_ref.get_ref()
	if value == null or not is_instance_valid(value):
		return null
	return value as ShipUnit


func set_target_ship(ship: ShipUnit) -> void:
	target_ship_ref = weakref(ship) \
		if ship != null and is_instance_valid(ship) else null


func duplicate_command() -> DiveBombCommand:
	var copy := DiveBombCommand.new()
	copy.command_id = command_id
	copy.target_point = target_point
	copy.target_velocity = target_velocity
	copy.dispersion_radius_m = dispersion_radius_m
	copy.target_ship_ref = target_ship_ref
	return copy
