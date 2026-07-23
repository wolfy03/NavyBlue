extends RefCounted
class_name WeaponDatabase

const DEFAULT_WEAPON_ID := "destroyer_cannon"
const WEAPON_PATHS := {
	"destroyer_cannon": "res://resources/weapons/destroyer_cannon.tres",
	"cruiser_cannon": "res://resources/weapons/cruiser_cannon.tres",
	"battleship_cannon": "res://resources/weapons/battleship_cannon.tres",
	"carrier_secondary": "res://resources/weapons/carrier_secondary.tres",
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
