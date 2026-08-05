extends RefCounted
class_name DiveBombResolvedTarget
## The answer to a DiveBombTargetRequest: either a ship to track and predict,
## the designated world position as a fixed aim point, or nothing.
##
## Ship references are weak; consumers read the live position/velocity while
## the ship survives and keep the last stored aim point after it is gone.

enum TargetType {
	WORLD_POSITION,
	SHIP,
	INVALID,
}

var type := TargetType.INVALID

var designated_world_position := Vector3.ZERO
var resolved_aim_position := Vector3.ZERO

var target_velocity := Vector3.ZERO

var ship_ref: WeakRef
var ship_instance_id := 0

var distance_from_designation_m := 0.0
var resolution_reason: StringName = &""


func get_ship() -> ShipUnit:
	if type != TargetType.SHIP or ship_ref == null:
		return null
	var value: Variant = ship_ref.get_ref()
	if value == null or not is_instance_valid(value):
		return null
	var ship := value as ShipUnit
	if ship == null or ship.is_queued_for_deletion() or not ship.is_alive():
		return null
	return ship


func is_ship_target() -> bool:
	return type == TargetType.SHIP


func is_position_target() -> bool:
	return type == TargetType.WORLD_POSITION


func is_valid() -> bool:
	return type != TargetType.INVALID


## True for a ship target whose ship no longer exists: the attack must either
## reacquire (approach) or hold the last aim point (committed dive).
func is_ship_target_lost() -> bool:
	return type == TargetType.SHIP and get_ship() == null


## Aim point for solving: the ship's live position while it survives, the
## last known/designated point otherwise. Refreshes the stored aim so a later
## loss keeps attacking where the ship was last seen.
func get_aim_position() -> Vector3:
	var ship := get_ship()
	if ship != null:
		resolved_aim_position = ship.global_position
	return resolved_aim_position


## Target velocity for lead prediction: live ship velocity while it
## survives, Vector3.ZERO for position targets and lost ships.
func get_target_velocity() -> Vector3:
	var ship := get_ship()
	if ship != null:
		target_velocity = ship.get_world_velocity()
		return target_velocity
	if type == TargetType.SHIP:
		# Lost ship: aim at the last point without stale lead.
		return Vector3.ZERO
	return target_velocity


func get_debug_snapshot() -> Dictionary:
	var ship := get_ship()
	return {
		"resolved_target_type": TargetType.keys()[int(type)],
		"resolved_target_ship_id": ship_instance_id,
		"resolved_target_ship_name": ship.name if ship != null else "",
		"resolved_target_position": resolved_aim_position,
		"resolved_target_velocity": target_velocity,
		"resolved_target_distance_from_designation_m":
			distance_from_designation_m,
		"target_resolution_reason": resolution_reason,
	}
