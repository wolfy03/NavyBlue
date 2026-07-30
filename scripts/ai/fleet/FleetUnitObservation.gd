extends RefCounted
class_name FleetUnitObservation

var ship_ref: WeakRef
var distance_m := 0.0
var strategic_value := 1.0
var sustained_dps := 0.0
var ready_salvo_damage := 0.0
var torpedo_salvo_damage := 0.0
var cannon_sustained_dps := 0.0
var assigned_attacker_count := 0
var emergency := false
var raw_score := 0.0
var selection_score := 0.0


func get_ship() -> ShipUnit:
	return ship_ref.get_ref() as ShipUnit if ship_ref != null else null
