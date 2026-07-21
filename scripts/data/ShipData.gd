extends Resource
class_name ShipData

enum ShipClass {
	DESTROYER,
	CRUISER,
	BATTLESHIP,
	AIRCRAFT_CARRIER,
}

@export var id := ""
@export var display_name := ""
@export var ship_class: ShipClass = ShipClass.DESTROYER
@export var max_forward_speed := 18.0
@export var max_reverse_speed := 7.0
@export var engine_response := 0.55
@export var turn_rate_degrees := 28.0
@export var hull_size := Vector3(2.2, 0.8, 7.0)
@export var turret_count := 2
@export var turret_spacing := 1.8
@export var shell_muzzle_velocity := 34.0
@export var reload_seconds := 1.2
@export var defense_stats: ShipDefenseStats
