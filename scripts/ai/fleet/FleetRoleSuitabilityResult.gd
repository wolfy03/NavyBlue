extends RefCounted
class_name FleetRoleSuitabilityResult

var ship: ShipUnit
var role := FleetMemberContext.TacticalRole.LINE_COMBATANT
var score := -INF
var suitable := false
var reason: StringName
