extends SceneTree

var _failures := PackedStringArray()
var _arena: Node3D
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var owner_data := _database.get_ship("dd_bluewind").duplicate(true) as ShipData
	owner_data.secondary_battery_layout = null
	owner_data.weapon_slots[0].battery_role = BatteryRole.Type.SECONDARY
	owner_data.weapon_slots[1].battery_role = BatteryRole.Type.SECONDARY
	var owner := _spawn(owner_data, &"player", Vector3.ZERO)
	var near_target := _spawn(
		_database.get_ship("dd_bluewind").duplicate(true) as ShipData,
		&"enemy",
		Vector3(0.0, 0.0, -2500.0)
	)
	var far_target := _spawn(
		_database.get_ship("bb_ironwake").duplicate(true) as ShipData,
		&"enemy",
		Vector3(0.0, 0.0, -7000.0)
	)
	await physics_frame
	var mounts := owner.combat.get_secondary_cannon_mounts()
	var selector := SecondaryBatteryTargetSelector.new()
	var profile := SecondaryBatteryProfile.new()
	var result := selector.select_target(
		owner,
		mounts,
		[far_target, near_target],
		profile
	)
	_check(result.target == near_target, "closer in-range hostile wins base scoring")
	profile.prefer_main_target = true
	profile.main_target_score_bonus = 3.0
	var preferred := selector.select_target(
		owner,
		mounts,
		[near_target, far_target],
		profile,
		far_target
	)
	_check(preferred.target == far_target, "valid main target receives score bonus")
	mounts[0].runtime_stats.range_multiplier = 0.4
	mounts[1].runtime_stats.range_multiplier = 1.0
	var mixed_context := selector.evaluate_candidate(
		owner,
		mounts,
		far_target,
		profile
	)
	_check(
		mixed_context.engaging_mount_count == 1,
		"mixed ranges count only the long-range secondary at 7 km"
	)
	mounts[1].runtime_stats.range_multiplier = 0.4
	var mixed := selector.select_target(
		owner,
		mounts,
		[far_target, near_target],
		profile
	)
	_check(mixed.target == near_target, "out-of-range main target is never forced")
	_arena.queue_free()
	await process_frame
	print("SECONDARY_BATTERY_SELECTOR_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _spawn(data: ShipData, team: StringName, position: Vector3) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	ship.setup(data, team, true, Color.WHITE)
	_arena.add_child(ship)
	ship.global_position = position
	return ship


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failures.append(description)
	push_error("SECONDARY BATTERY SELECTOR: %s" % description)
