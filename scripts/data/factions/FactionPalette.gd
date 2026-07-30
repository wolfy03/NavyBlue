extends Resource
class_name FactionPalette

const REQUIRED_FACTIONS: Array[StringName] = [
	FactionRelations.PLAYER,
	FactionRelations.ALLY,
	FactionRelations.ENEMY,
	FactionRelations.NEUTRAL,
]

@export var factions: Array[FactionData] = []


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen_ids: Dictionary = {}
	var seen_resources: Dictionary = {}
	for index in factions.size():
		var faction := factions[index]
		if faction == null:
			errors.append("factions[%d] must be a FactionData Resource." % index)
			continue
		errors.append_array(faction.validate())
		if seen_ids.has(faction.id):
			errors.append("Duplicate faction id: %s" % faction.id)
		else:
			seen_ids[faction.id] = true
		var resource_id := faction.get_instance_id()
		if seen_resources.has(resource_id):
			errors.append("FactionData Resource is registered more than once.")
		else:
			seen_resources[resource_id] = true
	for required_id in REQUIRED_FACTIONS:
		if not seen_ids.has(required_id):
			errors.append("Missing required faction: %s" % required_id)
	return errors


func get_faction(faction_id: StringName) -> FactionData:
	for faction in factions:
		if faction != null and faction.id == faction_id:
			return faction
	return null


func get_color(faction_id: StringName) -> Color:
	var faction := get_faction(faction_id)
	if faction == null:
		push_warning("Unknown faction id: %s" % faction_id)
	return faction.primary_color if faction != null else Color(0.5, 0.5, 0.5)
