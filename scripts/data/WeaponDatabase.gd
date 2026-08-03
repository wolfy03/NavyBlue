extends RefCounted
class_name WeaponDatabase

const DEFAULT_WEAPON_ID := "destroyer_cannon"
const WEAPON_PATHS := {
	"destroyer_cannon": "res://resources/weapons/destroyer_cannon.tres",
	"cruiser_cannon": "res://resources/weapons/cruiser_cannon.tres",
	"battleship_cannon": "res://resources/weapons/battleship_cannon.tres",
	"naval_gun_100mm": "res://resources/weapons/naval_gun_100mm.tres",
	"destroyer_torpedo_launcher": "res://resources/weapons/destroyer_torpedo_launcher.tres",
	"cruiser_torpedo_launcher": "res://resources/weapons/cruiser_torpedo_launcher.tres",
}

func get_weapon(id: String) -> WeaponData:
	var resolved_id := id if WEAPON_PATHS.has(id) else DEFAULT_WEAPON_ID
	if resolved_id != id:
		push_warning("Unknown weapon id '%s'. Falling back to %s." % [id, DEFAULT_WEAPON_ID])
	var path := str(WEAPON_PATHS[resolved_id])
	var data := load(path) as WeaponData
	if data != null:
		return data
	push_warning("Failed to load weapon data: %s" % path)
	if resolved_id != DEFAULT_WEAPON_ID:
		return load(str(WEAPON_PATHS[DEFAULT_WEAPON_ID])) as WeaponData
	var fallback := WeaponData.new()
	fallback.id = DEFAULT_WEAPON_ID
	return fallback


func find_weapon(id: String) -> WeaponData:
	if not WEAPON_PATHS.has(id):
		return null
	return load(str(WEAPON_PATHS[id])) as WeaponData
