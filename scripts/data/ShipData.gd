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
@export_category("Mobility (SI units)")
@export var max_speed_mps := 42.0
@export var cruise_speed_mps := 34.0
@export var max_reverse_speed_mps := 8.0
@export var acceleration_mps2 := 2.1
@export var deceleration_mps2 := 3.0
@export var max_turn_rate_deg_sec := 7.0
@export var turn_acceleration_deg_sec2 := 2.5
@export var arrival_slowdown_distance_m := 700.0
@export var minimum_turning_speed_mps := 8.0
@export var navigation_safety_radius_m := 90.0

# Compatibility aliases retained for upgrades and older serialized resources.
@export var max_forward_speed := 42.0
@export var max_reverse_speed := 8.0
@export var engine_response := 0.55
@export var turn_rate_degrees := 7.0
@export var hull_size := Vector3(2.2, 0.8, 7.0)
@export var turret_count := 2
@export var turret_spacing := 1.8
@export_category("Weapons (SI units)")
@export var shell_muzzle_velocity := 34.0
@export var maximum_firing_range_m := 12000.0
@export var reload_seconds := 1.2
@export var defense_stats: ShipDefenseStats
