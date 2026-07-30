extends RefCounted
class_name ShipCreationResult

var ship: ShipUnit
var requested_ship_id: StringName
var resolved_ship_id: StringName
var used_fallback := false
var error: String


func is_success() -> bool:
	return ship != null and is_instance_valid(ship)
