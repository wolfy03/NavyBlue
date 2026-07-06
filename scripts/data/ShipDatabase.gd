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
	ship.max_forward_speed = data["max_forward_speed"]
	ship.max_reverse_speed = data["max_reverse_speed"]
	ship.engine_response = data["engine_response"]
	ship.turn_rate_degrees = data["turn_rate_degrees"]
	ship.hull_size = data["hull_size"]
	ship.turret_count = data["turret_count"]
	ship.turret_spacing = data["turret_spacing"]
	ship.shell_muzzle_velocity = data["shell_muzzle_velocity"]
	ship.reload_seconds = data["reload_seconds"]
	return ship

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
			"max_forward_speed": 24.0,
			"max_reverse_speed": 10.0,
			"engine_response": 0.8,
			"turn_rate_degrees": 42.0,
			"hull_size": Vector3(1.6, 0.55, 5.4),
			"turret_count": 2,
			"turret_spacing": 1.55,
			"shell_muzzle_velocity": 34.0,
			"reload_seconds": 0.85,
		},
		"cl_tidebreaker": {
			"display_name": "Tidebreaker CL",
			"ship_class": ShipClass.CRUISER,
			"max_forward_speed": 19.0,
			"max_reverse_speed": 8.0,
			"engine_response": 0.62,
			"turn_rate_degrees": 30.0,
			"hull_size": Vector3(2.3, 0.75, 7.7),
			"turret_count": 3,
			"turret_spacing": 1.95,
			"shell_muzzle_velocity": 38.0,
			"reload_seconds": 1.25,
		},
		"bb_ironwake": {
			"display_name": "Ironwake BB",
			"ship_class": ShipClass.BATTLESHIP,
			"max_forward_speed": 14.0,
			"max_reverse_speed": 5.2,
			"engine_response": 0.38,
			"turn_rate_degrees": 17.0,
			"hull_size": Vector3(3.4, 1.0, 10.4),
			"turret_count": 4,
			"turret_spacing": 2.25,
			"shell_muzzle_velocity": 45.0,
			"reload_seconds": 2.0,
		},
		"cv_seabastion": {
			"display_name": "Seabastion CV",
			"ship_class": ShipClass.AIRCRAFT_CARRIER,
			"max_forward_speed": 13.0,
			"max_reverse_speed": 4.5,
			"engine_response": 0.32,
			"turn_rate_degrees": 14.0,
			"hull_size": Vector3(4.4, 0.95, 12.0),
			"turret_count": 1,
			"turret_spacing": 1.0,
			"shell_muzzle_velocity": 28.0,
			"reload_seconds": 1.7,
		},
	}
