extends SceneTree

const EXPECTED_MOUNTS_PER_SIDE := {
	"dd_bluewind": 3,
	"cl_tidebreaker": 10,
	"bb_ironwake": 15,
	"cv_seabastion": 6,
}
const SHIP_SCENE: PackedScene = preload("res://scenes/unit/ship.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var database := ShipDatabase.new()
	for ship_id_value in EXPECTED_MOUNTS_PER_SIDE:
		var ship_id := str(ship_id_value)
		await _test_ship_layout(
			database.get_ship(ship_id),
			ship_id,
			int(EXPECTED_MOUNTS_PER_SIDE[ship_id_value])
		)
	for failure in _failures:
		push_error("SHIP CLASS SECONDARY BATTERY LAYOUT TEST: %s" % failure)
	print(
		"SHIP_CLASS_SECONDARY_BATTERY_LAYOUT_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _test_ship_layout(
		ship_data: ShipData,
		ship_id: String,
		expected_per_side: int
) -> void:
	_check(ship_data != null, "%s ShipData loads" % ship_id)
	if ship_data == null:
		return
	var layout: Resource = ship_data.secondary_battery_layout
	_check(layout != null, "%s has a secondary layout" % ship_id)
	if layout == null:
		return
	var validation_errors := PackedStringArray(["missing validate()"])
	if layout.has_method(&"validate"):
		var validation_value: Variant = layout.call(&"validate")
		if validation_value is PackedStringArray:
			validation_errors = validation_value
	_check(
		validation_errors.is_empty(),
		"%s secondary layout validates" % ship_id
	)
	var layout_weapon_id := str(layout.get(&"weapon_id"))
	var port_count := 0
	var starboard_count := 0
	var slot_ids: Dictionary = {}
	var loadout := ShipWeaponLoadout.from_ship_data(ship_data)
	for slot in ship_data.get_runtime_weapon_slots():
		if slot == null or slot.battery_role != BatteryRole.Type.SECONDARY:
			continue
		var slot_key := String(slot.slot_id)
		_check(not slot_ids.has(slot_key), "%s has unique slot %s" % [ship_id, slot_key])
		slot_ids[slot_key] = true
		_check(
			loadout.get_weapon_id(slot.slot_id) == layout_weapon_id,
			"%s loadout includes %s" % [ship_id, slot_key]
		)
		_check(
			absf(slot.local_position.z) <= ship_data.hull_size.z * 0.5,
			"%s slot %s stays within hull length" % [ship_id, slot_key]
		)
		match slot.mount_side:
			WeaponTypes.MountSide.PORT:
				port_count += 1
				_check(
					slot.local_position.x < 0.0
						and is_equal_approx(
							slot.local_rotation_degrees.y,
							90.0
						),
					"%s port slot %s faces outboard" % [ship_id, slot_key]
				)
			WeaponTypes.MountSide.STARBOARD:
				starboard_count += 1
				_check(
					slot.local_position.x > 0.0
						and is_equal_approx(
							slot.local_rotation_degrees.y,
							-90.0
						),
					"%s starboard slot %s faces outboard" % [ship_id, slot_key]
				)
			_:
				_check(false, "%s slot %s has a side" % [ship_id, slot_key])
	_check(
		port_count == expected_per_side,
		"%s has %d port secondaries" % [ship_id, expected_per_side]
	)
	_check(
		starboard_count == expected_per_side,
		"%s has %d starboard secondaries" % [ship_id, expected_per_side]
	)
	var runtime_ship := SHIP_SCENE.instantiate() as ShipUnit
	runtime_ship.setup(
		ship_data.duplicate(true) as ShipData,
		&"ally",
		false,
		Color.WHITE
	)
	root.add_child(runtime_ship)
	await process_frame
	_check(
		runtime_ship.combat.get_secondary_cannon_mounts().size()
			== expected_per_side * 2,
		"%s instantiates %d secondary CannonMount nodes"
			% [ship_id, expected_per_side * 2]
	)
	runtime_ship.queue_free()
	await process_frame


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
