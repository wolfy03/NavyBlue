extends RefCounted
class_name FleetTacticalDecision

var primary_target: ShipUnit
var primary_score := 0.0
var secondary_targets: Array[ShipUnit] = []
var emergency_targets: Array[ShipUnit] = []
var member_orders: Array[FleetMemberOrder] = []
var reason: StringName
