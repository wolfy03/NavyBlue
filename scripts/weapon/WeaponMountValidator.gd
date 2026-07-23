extends RefCounted
class_name WeaponMountValidator


static func can_mount(slot: ShipWeaponSlotData, weapon: WeaponData) -> bool:
	return validate(slot, weapon).valid


static func validate(
		slot: ShipWeaponSlotData,
		weapon: WeaponData
) -> WeaponMountValidationResult:
	if slot == null:
		return WeaponMountValidationResult.new().setup(false, "missing_slot")
	if weapon == null:
		return WeaponMountValidationResult.new().setup(false, "missing_weapon")
	if int(weapon.required_slot_size) > int(slot.slot_size):
		return WeaponMountValidationResult.new().setup(false, "slot_too_small")
	if not slot.allowed_weapon_types.is_empty() \
			and weapon.weapon_type not in slot.allowed_weapon_types:
		return WeaponMountValidationResult.new().setup(false, "weapon_type_not_allowed")
	return WeaponMountValidationResult.new().setup(true)
