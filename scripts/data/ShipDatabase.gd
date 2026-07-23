extends RefCounted
class_name ShipDatabase

const DEFAULT_SHIP_ID := "dd_bluewind"
const SHIP_PATHS := {
	"dd_bluewind": "res://resources/ships/dd_bluewind.tres",
	"cl_tidebreaker": "res://resources/ships/cl_tidebreaker.tres",
	"bb_ironwake": "res://resources/ships/bb_ironwake.tres",
	"cv_seabastion": "res://resources/ships/cv_seabastion.tres",
}

func get_ship(id: String) -> ShipData:
	var resolved_id := id if SHIP_PATHS.has(id) else DEFAULT_SHIP_ID
	if resolved_id != id:
		push_warning("Unknown ship id '%s'. Falling back to %s." % [id, DEFAULT_SHIP_ID])
	var path := str(SHIP_PATHS[resolved_id])
	var data := load(path) as ShipData
	if data != null:
		return data
	push_warning("Failed to load ship data: %s" % path)
	if resolved_id != DEFAULT_SHIP_ID:
		return load(str(SHIP_PATHS[DEFAULT_SHIP_ID])) as ShipData
	var fallback := ShipData.new()
	fallback.id = DEFAULT_SHIP_ID
	return fallback

func class_label(value: int) -> String:
	match value:
		ShipData.ShipClass.DESTROYER:
			return "Destroyer"
		ShipData.ShipClass.CRUISER:
			return "Cruiser"
		ShipData.ShipClass.BATTLESHIP:
			return "Battleship"
		ShipData.ShipClass.AIRCRAFT_CARRIER:
			return "Aircraft Carrier"
	return "Unknown"
