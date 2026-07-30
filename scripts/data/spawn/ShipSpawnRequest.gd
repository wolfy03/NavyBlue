extends RefCounted
class_name ShipSpawnRequest

var ship_id: StringName
var team: StringName = FactionRelations.NEUTRAL
var fleet_id: StringName
var display_name: String
var transform := Transform3D.IDENTITY
var is_player := false
var color := Color.WHITE
var weapon_loadout: ShipWeaponLoadout
var weapon_runtime_stats: Dictionary = {}
var allow_player_fallback := false
