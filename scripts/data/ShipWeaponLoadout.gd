extends Resource
class_name ShipWeaponLoadout

## Weapon ids that were renamed after Save version 2 shipped. Applied on load
## only: saved data is translated to the current id, and to_dictionary always
## writes the current id, so an alias is never persisted again. Renaming a
## weapon therefore needs no save-version bump.
const LEGACY_WEAPON_ID_ALIASES := {
	"carrier_secondary": "naval_gun_100mm",
}

@export var entries: Array[WeaponLoadoutEntryData] = []


## Translates a persisted weapon id to the current one. Unknown ids pass
## through unchanged so validation and slot repair still report them.
static func resolve_weapon_id(weapon_id: String) -> String:
	return str(LEGACY_WEAPON_ID_ALIASES.get(weapon_id, weapon_id))


func get_weapon_id(slot_id: StringName) -> String:
	for entry in entries:
		if entry != null and entry.slot_id == slot_id:
			return entry.weapon_id
	return ""


func set_weapon_id(slot_id: StringName, weapon_id: String) -> void:
	var new_entry := WeaponLoadoutEntryData.new()
	new_entry.slot_id = slot_id
	new_entry.weapon_id = weapon_id
	entries.append(new_entry)
	normalize()


func normalize() -> void:
	# Last duplicate wins so the newest migrated or user-selected value survives.
	var latest_by_slot: Dictionary = {}
	for entry in entries:
		if entry == null or entry.slot_id.is_empty():
			continue
		latest_by_slot[String(entry.slot_id)] = entry.weapon_id
	var slot_ids: Array = latest_by_slot.keys()
	slot_ids.sort()
	entries.clear()
	for slot_id_value in slot_ids:
		var entry := WeaponLoadoutEntryData.new()
		entry.slot_id = StringName(str(slot_id_value))
		entry.weapon_id = str(latest_by_slot[slot_id_value])
		entries.append(entry)


func validate_against_ship(
		ship_data: ShipData,
		weapon_database: RefCounted
) -> Array[String]:
	var errors: Array[String] = []
	if ship_data == null:
		errors.append("Cannot validate weapon loadout without ShipData.")
		return errors
	if weapon_database == null or not weapon_database.has_method(&"find_weapon"):
		errors.append("Cannot validate weapon loadout without WeaponDatabase.find_weapon().")
		return errors
	var seen_slots: Dictionary = {}
	for entry in entries:
		if entry == null:
			errors.append("Weapon loadout contains a null entry.")
			continue
		if entry.slot_id.is_empty():
			errors.append("Weapon loadout contains an empty slot_id.")
			continue
		var slot_key := String(entry.slot_id)
		if seen_slots.has(slot_key):
			errors.append("Weapon loadout contains duplicate slot_id '%s'." % slot_key)
		seen_slots[slot_key] = true
		var slot := _find_slot(ship_data, entry.slot_id)
		if slot == null:
			errors.append(
				"Ship '%s' has no weapon slot '%s'." % [ship_data.id, slot_key]
			)
			continue
		if entry.weapon_id.is_empty():
			errors.append("Weapon slot '%s' has an empty weapon_id." % slot_key)
			continue
		var weapon := weapon_database.call(&"find_weapon", entry.weapon_id) \
			as WeaponData
		if weapon == null:
			errors.append(
				"Weapon '%s' in slot '%s' does not exist."
				% [entry.weapon_id, slot_key]
			)
			continue
		errors.append_array(_get_weapon_errors(slot, weapon))
	return errors


func repair_against_ship(
		ship_data: ShipData,
		weapon_database: RefCounted
) -> Array[String]:
	var warnings: Array[String] = []
	if ship_data == null:
		warnings.append("Cannot repair weapon loadout without ShipData.")
		entries.clear()
		return warnings
	if weapon_database == null or not weapon_database.has_method(&"find_weapon"):
		warnings.append("Cannot repair weapon loadout without WeaponDatabase.find_weapon().")
		return warnings

	var latest_by_slot: Dictionary = {}
	for entry in entries:
		if entry == null:
			warnings.append("Removed null weapon loadout entry.")
			continue
		if entry.slot_id.is_empty():
			warnings.append("Removed weapon loadout entry with empty slot_id.")
			continue
		var slot_key := String(entry.slot_id)
		if latest_by_slot.has(slot_key):
			warnings.append(
				"Collapsed duplicate weapon slot '%s'; kept the last value."
				% slot_key
			)
		latest_by_slot[slot_key] = entry.weapon_id

	var repaired_entries: Array[WeaponLoadoutEntryData] = []
	var slot_ids: Array = latest_by_slot.keys()
	slot_ids.sort()
	for slot_id_value in slot_ids:
		var slot_key := str(slot_id_value)
		var slot_id := StringName(slot_key)
		var slot := _find_slot(ship_data, slot_id)
		if slot == null:
			warnings.append(
				"Removed unknown weapon slot '%s' from ship '%s'."
				% [slot_key, ship_data.id]
			)
			continue
		var requested_weapon_id := str(latest_by_slot[slot_id_value])
		var weapon := weapon_database.call(
			&"find_weapon",
			requested_weapon_id
		) as WeaponData if not requested_weapon_id.is_empty() else null
		var validation_errors := _get_weapon_errors(slot, weapon)
		if weapon == null or not validation_errors.is_empty():
			var fallback_id := slot.default_weapon_id
			var fallback := weapon_database.call(&"find_weapon", fallback_id) \
				as WeaponData if not fallback_id.is_empty() else null
			var fallback_errors := _get_weapon_errors(slot, fallback)
			if fallback == null or not fallback_errors.is_empty():
				warnings.append(
					"Cleared invalid weapon '%s' from slot '%s'; default '%s' is also invalid."
					% [requested_weapon_id, slot_key, fallback_id]
				)
				continue
			warnings.append(
				"Replaced invalid weapon '%s' in slot '%s' with default '%s'."
				% [requested_weapon_id, slot_key, fallback_id]
			)
			requested_weapon_id = fallback_id
		var repaired := WeaponLoadoutEntryData.new()
		repaired.slot_id = slot_id
		repaired.weapon_id = requested_weapon_id
		repaired_entries.append(repaired)

	entries = repaired_entries
	normalize()
	return warnings


func duplicate_loadout() -> ShipWeaponLoadout:
	var result := duplicate(true) as ShipWeaponLoadout
	result.normalize()
	return result


func to_dictionary() -> Dictionary:
	normalize()
	var serialized_entries: Array[Dictionary] = []
	for entry in entries:
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
		var entry := WeaponLoadoutEntryData.new()
		entry.slot_id = StringName(str(entry_data.get("slot_id", "")))
		entry.weapon_id = resolve_weapon_id(
			str(entry_data.get("weapon_id", ""))
		)
		loadout.entries.append(entry)
	loadout.normalize()
	return loadout


static func from_ship_data(ship_data: ShipData) -> ShipWeaponLoadout:
	var loadout := ShipWeaponLoadout.new()
	if ship_data == null:
		return loadout
	for slot in ship_data.get_runtime_weapon_slots():
		if slot != null and not slot.slot_id.is_empty():
			loadout.set_weapon_id(slot.slot_id, slot.default_weapon_id)
	return loadout


static func _find_slot(
		ship_data: ShipData,
		slot_id: StringName
) -> ShipWeaponSlotData:
	if ship_data == null:
		return null
	for slot in ship_data.get_runtime_weapon_slots():
		if slot != null and slot.slot_id == slot_id:
			return slot
	return null


static func _get_weapon_errors(
		slot: ShipWeaponSlotData,
		weapon: WeaponData
) -> Array[String]:
	var errors: Array[String] = []
	if slot == null:
		errors.append("Weapon validation is missing its slot.")
		return errors
	if weapon == null:
		errors.append("Weapon slot '%s' references a missing weapon." % String(slot.slot_id))
		return errors
	var validation := WeaponMountValidator.validate(slot, weapon)
	if not validation.valid:
		errors.append(
			"Weapon '%s' is invalid for slot '%s': %s."
			% [weapon.id, String(slot.slot_id), validation.reason]
		)
	if weapon.mount_scene == null:
		errors.append("Weapon '%s' has no mount_scene." % weapon.id)
	elif not weapon.mount_scene.can_instantiate():
		errors.append("Weapon '%s' mount_scene cannot instantiate." % weapon.id)
	else:
		var mount_node := weapon.mount_scene.instantiate()
		if not mount_node is WeaponMount:
			errors.append(
				"Weapon '%s' mount_scene does not inherit WeaponMount." % weapon.id
			)
		if mount_node != null:
			mount_node.free()
	if weapon.projectile_data == null:
		errors.append("Weapon '%s' has no projectile_data." % weapon.id)
	if weapon.projectile_scene == null:
		errors.append("Weapon '%s' has no projectile_scene." % weapon.id)
	return errors
