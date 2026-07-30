extends RefCounted
class_name FleetMemberOrder

enum OrderType {
	HOLD,
	APPROACH,
	MAINTAIN_RANGE,
	FOCUS_FIRE,
	RETREAT,
	REGROUP,
}

var ship: ShipUnit
var target: ShipUnit
var destination := Vector3.ZERO
var order_type := OrderType.HOLD
var reason: StringName
