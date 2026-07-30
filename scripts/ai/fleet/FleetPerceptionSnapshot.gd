extends RefCounted
class_name FleetPerceptionSnapshot

var fleet_center := Vector3.ZERO
var own_units: Array[ShipUnit] = []
var observations: Array[FleetUnitObservation] = []


func get_valid_targets() -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for observation in observations:
		var ship := observation.get_ship()
		if ship != null and is_instance_valid(ship) and ship.is_alive():
			result.append(ship)
	return result
