extends RefCounted
class_name FleetRoleAssignment

var ship: ShipUnit
var role := FleetMemberContext.TacticalRole.LINE_COMBATANT
var score := -INF
var reason: StringName
