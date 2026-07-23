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
	if weapon.mount_scene == null:
		return WeaponMountValidationResult.new().setup(false, "missing_mount_scene")
	if not weapon.mount_scene.can_instantiate():
		return WeaponMountValidationResult.new().setup(false, "invalid_mount_scene")
	var mount_node := weapon.mount_scene.instantiate()
	var valid_mount := mount_node is WeaponMount
	if mount_node != null:
		mount_node.free()
	if not valid_mount:
		return WeaponMountValidationResult.new().setup(
			false,
			"mount_scene_must_inherit_weapon_mount"
		)
	if weapon.projectile_data == null:
		return WeaponMountValidationResult.new().setup(false, "missing_projectile_data")
	if weapon.projectile_scene == null:
		return WeaponMountValidationResult.new().setup(false, "missing_projectile_scene")
	return WeaponMountValidationResult.new().setup(true)
