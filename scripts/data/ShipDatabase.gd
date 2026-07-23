extends RefCounted
class_name ShipDatabase

const SHIP_DATA_SCRIPT := preload("res://scripts/data/ShipData.gd")

enum ShipClass {
	DESTROYER,
	CRUISER,
	BATTLESHIP,
	AIRCRAFT_CARRIER,
}

func get_ship(id: String) -> Resource:
	var definitions := _definitions()
	if not definitions.has(id):
		push_warning("Unknown ship id '%s'. Falling back to starter destroyer." % id)
		id = "dd_bluewind"

	var data: Dictionary = definitions[id]
	var ship: Resource = SHIP_DATA_SCRIPT.new()
	ship.id = id
	ship.display_name = data["display_name"]
	ship.ship_class = data["ship_class"]
	ship.max_speed_mps = data["max_speed_mps"]
	ship.cruise_speed_mps = data["cruise_speed_mps"]
	ship.max_reverse_speed_mps = data["max_reverse_speed_mps"]
	ship.acceleration_mps2 = data["acceleration_mps2"]
	ship.deceleration_mps2 = data["deceleration_mps2"]
	ship.max_turn_rate_deg_sec = data["max_turn_rate_deg_sec"]
	ship.turn_acceleration_deg_sec2 = data["turn_acceleration_deg_sec2"]
	ship.arrival_slowdown_distance_m = data["arrival_slowdown_distance_m"]
	ship.minimum_turning_speed_mps = data["minimum_turning_speed_mps"]
	ship.navigation_safety_radius_m = data["navigation_safety_radius_m"]
	ship.max_forward_speed = ship.max_speed_mps
	ship.max_reverse_speed = ship.max_reverse_speed_mps
	ship.engine_response = data["engine_response"]
	ship.turn_rate_degrees = ship.max_turn_rate_deg_sec
	ship.hull_size = data["hull_size"]
	ship.turret_count = data["turret_count"]
	ship.turret_spacing = data["turret_spacing"]
	ship.shell_muzzle_velocity = data["shell_muzzle_velocity"]
	ship.maximum_firing_range_m = data["maximum_firing_range_m"]
	ship.reload_seconds = data["reload_seconds"]
	ship.defense_stats = _create_defense_stats(data)
	return ship


func _create_defense_stats(data: Dictionary) -> ShipDefenseStats:
	var defense := ShipDefenseStats.new()
	defense.max_hp = data["max_hp"]
	defense.current_hp = data["max_hp"]
	defense.belt_armor = data["belt_armor"]
	defense.deck_armor = data["deck_armor"]
	defense.bow_armor = data["bow_armor"]
	defense.stern_armor = data["stern_armor"]
	defense.superstructure_armor = data["superstructure_armor"]
	defense.damage_reduction = data["damage_reduction"]
	return defense

func class_label(value: int) -> String:
	match value:
		ShipClass.DESTROYER:
			return "Destroyer"
		ShipClass.CRUISER:
			return "Cruiser"
		ShipClass.BATTLESHIP:
			return "Battleship"
		ShipClass.AIRCRAFT_CARRIER:
			return "Aircraft Carrier"
	return "Unknown"

func _definitions() -> Dictionary:
	return {
		"dd_bluewind": {
			"display_name": "Bluewind DD",
			"ship_class": ShipClass.DESTROYER,
			"max_speed_mps": 46.0,
			"cruise_speed_mps": 36.0,
			"max_reverse_speed_mps": 10.0,
			"acceleration_mps2": 2.4,
			"deceleration_mps2": 3.4,
			"max_turn_rate_deg_sec": 8.0,
			"turn_acceleration_deg_sec2": 3.2,
			"arrival_slowdown_distance_m": 650.0,
			"minimum_turning_speed_mps": 8.0,
			"navigation_safety_radius_m": 90.0,
			"engine_response": 0.8,
			"hull_size": Vector3(18.0, 7.0, 125.0),
			"turret_count": 2,
			"turret_spacing": 54.0,
			"shell_muzzle_velocity": 760.0,
			"maximum_firing_range_m": 12000.0,
			"reload_seconds": 4.5,
			"max_hp": 140.0,
			"belt_armor": 45.0,
			"deck_armor": 24.0,
			"bow_armor": 20.0,
			"stern_armor": 18.0,
			"superstructure_armor": 10.0,
			"damage_reduction": 0.02,
		},
		"cl_tidebreaker": {
			"display_name": "Tidebreaker CL",
			"ship_class": ShipClass.CRUISER,
			"max_speed_mps": 34.0,
			"cruise_speed_mps": 27.0,
			"max_reverse_speed_mps": 8.0,
			"acceleration_mps2": 1.25,
			"deceleration_mps2": 1.8,
			"max_turn_rate_deg_sec": 5.0,
			"turn_acceleration_deg_sec2": 1.8,
			"arrival_slowdown_distance_m": 900.0,
			"minimum_turning_speed_mps": 7.0,
			"navigation_safety_radius_m": 130.0,
			"engine_response": 0.62,
			"hull_size": Vector3(23.0, 9.0, 190.0),
			"turret_count": 3,
			"turret_spacing": 52.0,
			"shell_muzzle_velocity": 820.0,
			"maximum_firing_range_m": 15000.0,
			"reload_seconds": 8.0,
			"max_hp": 280.0,
			"belt_armor": 85.0,
			"deck_armor": 42.0,
			"bow_armor": 35.0,
			"stern_armor": 30.0,
			"superstructure_armor": 18.0,
			"damage_reduction": 0.05,
		},
		"bb_ironwake": {
			"display_name": "Ironwake BB",
			"ship_class": ShipClass.BATTLESHIP,
			"max_speed_mps": 27.0,
			"cruise_speed_mps": 22.0,
			"max_reverse_speed_mps": 6.0,
			"acceleration_mps2": 0.7,
			"deceleration_mps2": 1.0,
			"max_turn_rate_deg_sec": 3.0,
			"turn_acceleration_deg_sec2": 0.9,
			"arrival_slowdown_distance_m": 1300.0,
			"minimum_turning_speed_mps": 6.0,
			"navigation_safety_radius_m": 180.0,
			"engine_response": 0.38,
			"hull_size": Vector3(33.0, 12.0, 270.0),
			"turret_count": 4,
			"turret_spacing": 62.0,
			"shell_muzzle_velocity": 790.0,
			"maximum_firing_range_m": 19000.0,
			"reload_seconds": 24.0,
			"max_hp": 650.0,
			"belt_armor": 180.0,
			"deck_armor": 95.0,
			"bow_armor": 80.0,
			"stern_armor": 70.0,
			"superstructure_armor": 30.0,
			"damage_reduction": 0.1,
		},
		"cv_seabastion": {
			"display_name": "Seabastion CV",
			"ship_class": ShipClass.AIRCRAFT_CARRIER,
			"max_speed_mps": 29.0,
			"cruise_speed_mps": 23.0,
			"max_reverse_speed_mps": 5.0,
			"acceleration_mps2": 0.65,
			"deceleration_mps2": 0.9,
			"max_turn_rate_deg_sec": 2.7,
			"turn_acceleration_deg_sec2": 0.8,
			"arrival_slowdown_distance_m": 1400.0,
			"minimum_turning_speed_mps": 6.0,
			"navigation_safety_radius_m": 200.0,
			"engine_response": 0.32,
			"hull_size": Vector3(40.0, 15.0, 300.0),
			"turret_count": 1,
			"turret_spacing": 1.0,
			"shell_muzzle_velocity": 720.0,
			"maximum_firing_range_m": 10000.0,
			"reload_seconds": 12.0,
			"max_hp": 420.0,
			"belt_armor": 70.0,
			"deck_armor": 55.0,
			"bow_armor": 38.0,
			"stern_armor": 32.0,
			"superstructure_armor": 16.0,
			"damage_reduction": 0.06,
		},
	}
