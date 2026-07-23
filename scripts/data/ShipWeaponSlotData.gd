extends Resource
class_name ShipWeaponSlotData

@export_category("Identity")
@export var slot_id: StringName
@export var display_name := ""

@export_category("Transform")
@export var local_position := Vector3.ZERO
@export var local_rotation_degrees := Vector3.ZERO
@export var local_scale := Vector3.ONE

@export_category("Compatibility")
@export var slot_size: WeaponTypes.SlotSize = WeaponTypes.SlotSize.MEDIUM
@export var allowed_weapon_types: Array[WeaponTypes.Type] = []
@export var mount_side: WeaponTypes.MountSide = WeaponTypes.MountSide.CENTERLINE

@export_category("Default Loadout")
@export var default_weapon_id := ""

@export_category("Traverse Limits")
@export var traverse_min_degrees := -180.0
@export var traverse_max_degrees := 180.0
@export var elevation_min_degrees := 0.0
@export var elevation_max_degrees := 60.0
