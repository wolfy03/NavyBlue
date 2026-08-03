extends Resource
class_name SecondaryBatteryLayout

@export_category("Loadout")
## General-purpose naval gun. The secondary role comes from
## slot_data.battery_role, not from the weapon identity, so the same WeaponData
## can serve as a main battery on another hull.
@export var weapon_id := "naval_gun_100mm"
@export_range(0, 64, 1) var port_mount_count := 0
@export_range(0, 64, 1) var starboard_mount_count := 0

@export_category("Placement")
@export var lateral_offset_m := 0.0
@export var vertical_position_m := 0.0
@export var longitudinal_start_m := 0.0
@export var longitudinal_end_m := 0.0
@export var mount_scale := Vector3.ONE

@export_category("Firing Arc")
@export_range(0.0, 180.0, 0.5) var traverse_half_arc_degrees := 90.5
@export_range(-90.0, 90.0, 0.5) var elevation_min_degrees := 0.0
@export_range(-90.0, 90.0, 0.5) var elevation_max_degrees := 80.0


func build_slots() -> Array[ShipWeaponSlotData]:
	var slots: Array[ShipWeaponSlotData] = []
	_append_side_slots(
		slots,
		WeaponTypes.MountSide.PORT,
		maxi(port_mount_count, 0)
	)
	_append_side_slots(
		slots,
		WeaponTypes.MountSide.STARBOARD,
		maxi(starboard_mount_count, 0)
	)
	return slots


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if weapon_id.is_empty():
		errors.append("Secondary battery weapon_id must not be empty.")
	if port_mount_count < 0 or starboard_mount_count < 0:
		errors.append("Secondary battery mount counts must be non-negative.")
	if lateral_offset_m <= 0.0:
		errors.append("Secondary battery lateral_offset_m must be positive.")
	if vertical_position_m < 0.0:
		errors.append("Secondary battery vertical_position_m must be non-negative.")
	if mount_scale.x <= 0.0 or mount_scale.y <= 0.0 \
			or mount_scale.z <= 0.0:
		errors.append("Secondary battery mount_scale must be positive.")
	if traverse_half_arc_degrees <= 0.0 \
			or traverse_half_arc_degrees > 180.0:
		errors.append(
			"Secondary battery traverse_half_arc_degrees must be in (0, 180]."
		)
	if elevation_max_degrees < elevation_min_degrees:
		errors.append(
			"Secondary battery elevation maximum must not be below its minimum."
		)
	return errors


func _append_side_slots(
		slots: Array[ShipWeaponSlotData],
		side: WeaponTypes.MountSide,
		count: int
) -> void:
	if count <= 0:
		return
	var is_port := side == WeaponTypes.MountSide.PORT
	var side_name := "port" if is_port else "starboard"
	var side_label := "Port" if is_port else "Starboard"
	var position_x := -absf(lateral_offset_m) \
		if is_port else absf(lateral_offset_m)
	var outboard_yaw := 90.0 if is_port else -90.0
	for index in range(count):
		var ratio := 0.5 if count == 1 else float(index) / float(count - 1)
		var slot := ShipWeaponSlotData.new()
		slot.slot_id = StringName(
			"secondary_%s_%02d" % [side_name, index + 1]
		)
		slot.display_name = "%s secondary mount %d" % [
			side_label,
			index + 1,
		]
		slot.local_position = Vector3(
			position_x,
			vertical_position_m,
			lerpf(longitudinal_start_m, longitudinal_end_m, ratio)
		)
		slot.local_rotation_degrees = Vector3(0.0, outboard_yaw, 0.0)
		slot.local_scale = mount_scale
		# Visual scale is configured independently; the existing automatic
		# secondary weapon requires a MEDIUM compatibility slot.
		slot.slot_size = WeaponTypes.SlotSize.MEDIUM
		slot.allowed_weapon_types = [WeaponTypes.Type.CANNON]
		slot.mount_side = side
		slot.battery_role = BatteryRole.Type.SECONDARY
		slot.default_weapon_id = weapon_id
		slot.traverse_min_degrees = -traverse_half_arc_degrees
		slot.traverse_max_degrees = traverse_half_arc_degrees
		slot.elevation_min_degrees = elevation_min_degrees
		slot.elevation_max_degrees = elevation_max_degrees
		slots.append(slot)
