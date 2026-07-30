extends Resource
class_name FactionPalette

@export var factions: Array[FactionData] = []


func get_faction(faction_id: StringName) -> FactionData:
	for faction in factions:
		if faction != null and faction.id == faction_id:
			return faction
	return null


func get_color(faction_id: StringName) -> Color:
	var faction := get_faction(faction_id)
	return faction.primary_color if faction != null else Color(0.5, 0.5, 0.5)
