extends Resource
class_name ShipWeaponLoadout

@export var entries: Array[WeaponLoadoutEntryData] = []


func get_weapon_id(slot_id: StringName) -> String:
	for entry in entries:
		if entry != null and entry.slot_id == slot_id:
			return entry.weapon_id
	return ""


func set_weapon_id(slot_id: StringName, weapon_id: String) -> void:
	for entry in entries:
		if entry != null and entry.slot_id == slot_id:
			entry.weapon_id = weapon_id
			return
	var new_entry := WeaponLoadoutEntryData.new()
	new_entry.slot_id = slot_id
	new_entry.weapon_id = weapon_id
	entries.append(new_entry)


func duplicate_loadout() -> ShipWeaponLoadout:
	return duplicate(true) as ShipWeaponLoadout


func to_dictionary() -> Dictionary:
	var serialized_entries: Array[Dictionary] = []
	for entry in entries:
		if entry == null or entry.slot_id.is_empty():
			continue
		serialized_entries.append({
			"slot_id": String(entry.slot_id),
			"weapon_id": entry.weapon_id,
		})
	return {"entries": serialized_entries}


static func from_dictionary(data: Dictionary) -> ShipWeaponLoadout:
	var loadout := ShipWeaponLoadout.new()
	var serialized_entries: Variant = data.get("entries", [])
	if not serialized_entries is Array:
		return loadout
	for entry_value in serialized_entries:
		if not entry_value is Dictionary:
			continue
		var entry_data := entry_value as Dictionary
		var slot_id := StringName(str(entry_data.get("slot_id", "")))
		if slot_id.is_empty():
			continue
		loadout.set_weapon_id(slot_id, str(entry_data.get("weapon_id", "")))
	return loadout


static func from_ship_data(ship_data: ShipData) -> ShipWeaponLoadout:
	var loadout := ShipWeaponLoadout.new()
	if ship_data == null:
		return loadout
	for slot in ship_data.weapon_slots:
		if slot != null and not slot.slot_id.is_empty():
			loadout.set_weapon_id(slot.slot_id, slot.default_weapon_id)
	return loadout
