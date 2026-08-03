extends SceneTree

var _failures := PackedStringArray()
var _arena: Node3D
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _mount_scene := preload("res://scenes/weapon/mounts/cannon_mount.tscn")
var _ship_database := ShipDatabase.new()
var _weapon_database := WeaponDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var shooter := _spawn_ship(&"enemy", Vector3.ZERO)
	var target := _spawn_ship(&"ally", Vector3(0.0, 0.0, 4000.0))
	var kept_mount := _spawn_mount(Vector3(0.0, 2.0, 5.0))
	var removed_mount := _spawn_mount(Vector3(0.0, 2.0, -5.0))
	await physics_frame
	var fire_control := ShipGunneryFireControl.new()
	fire_control.configure(
		preload("res://resources/ai_difficulty/gunnery_normal.tres"),
		GunneryCrewStats.new()
	)
	var both: Array[WeaponMount] = [kept_mount, removed_mount]
	fire_control.update(shooter, target, both)
	fire_control.bind_mount_provider(kept_mount)
	fire_control.bind_mount_provider(removed_mount)
	var kept_only: Array[WeaponMount] = [kept_mount]
	fire_control.update(shooter, target, kept_only)
	_check(
		removed_mount.shell_deviation_provider == null,
		"valid mount removed from a rebuilt group releases its provider"
	)
	_check(
		kept_mount.shell_deviation_provider == fire_control,
		"mount retained by the group keeps its provider"
	)
	removed_mount.free()
	fire_control.update(shooter, target, kept_only)
	_check(
		fire_control.get_group_session_for_mount(kept_mount) != null,
		"freed removed mount does not corrupt the surviving group"
	)
	_arena.queue_free()
	await process_frame
	print("GUNNERY_FREED_MOUNT_CLEANUP_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _spawn_ship(team: StringName, position: Vector3) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	ship.setup(
		_ship_database.get_ship("dd_bluewind").duplicate(true) as ShipData,
		team,
		true,
		Color.WHITE
	)
	_arena.add_child(ship)
	ship.global_position = position
	return ship


func _spawn_mount(position: Vector3) -> CannonMount:
	var mount := _mount_scene.instantiate() as CannonMount
	_arena.add_child(mount)
	mount.setup(
		_weapon_database.get_weapon("destroyer_cannon"),
		null,
		null,
		&"enemy"
	)
	mount.global_position = position
	return mount


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("GUNNERY FREED MOUNT CLEANUP: %s" % label)
