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
			"max_forward_speed": 24.0,
			"max_reverse_speed": 10.0,
			"engine_response": 0.8,
			"turn_rate_degrees": 42.0,
			"hull_size": Vector3(1.6, 0.55, 5.4),
			"turret_count": 2,
			"turret_spacing": 1.55,
			"shell_muzzle_velocity": 34.0,
			"reload_seconds": 0.85,
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
			"max_forward_speed": 19.0,
			"max_reverse_speed": 8.0,
			"engine_response": 0.62,
			"turn_rate_degrees": 30.0,
			"hull_size": Vector3(2.3, 0.75, 7.7),
			"turret_count": 3,
			"turret_spacing": 1.95,
			"shell_muzzle_velocity": 38.0,
			"reload_seconds": 1.25,
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
			"max_forward_speed": 14.0,
			"max_reverse_speed": 5.2,
			"engine_response": 0.38,
			"turn_rate_degrees": 17.0,
			"hull_size": Vector3(3.4, 1.0, 10.4),
			"turret_count": 4,
			"turret_spacing": 2.25,
			"shell_muzzle_velocity": 45.0,
			"reload_seconds": 2.0,
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
			"max_forward_speed": 13.0,
			"max_reverse_speed": 4.5,
			"engine_response": 0.32,
			"turn_rate_degrees": 14.0,
			"hull_size": Vector3(4.4, 0.95, 12.0),
			"turret_count": 1,
			"turret_spacing": 1.0,
			"shell_muzzle_velocity": 28.0,
			"reload_seconds": 1.7,
			"max_hp": 420.0,
			"belt_armor": 70.0,
			"deck_armor": 55.0,
			"bow_armor": 38.0,
			"stern_armor": 32.0,
			"superstructure_armor": 16.0,
			"damage_reduction": 0.06,
		},
	}
