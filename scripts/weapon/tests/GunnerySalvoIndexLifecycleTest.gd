extends SceneTree

const NORMAL: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)

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
	var mount_a := _spawn_mount(Vector3(0.0, 2.0, 10.0))
	var mount_b := _spawn_mount(Vector3(0.0, 2.0, -10.0))
	await physics_frame
	var mounts: Array[WeaponMount] = [mount_b, mount_a]
	var fire_control := ShipGunneryFireControl.new()
	fire_control.configure(NORMAL, GunneryCrewStats.new())
	fire_control.update(shooter, target, mounts)
	var first := fire_control.begin_salvo(&"destroyer_cannon")
	_check(first != null and first.salvo_index == 0, "first explicit salvo uses index zero")
	var first_seed := first.salvo_seed if first != null else 0
	fire_control.get_shell_deviation_radians(mount_a, 0, 1)
	var ordered_mounts: Array[WeaponMount] = [mount_a, mount_b]
	for _frame in 5:
		fire_control.update(shooter, target, ordered_mounts)
	var delayed_session := fire_control.get_group_session_for_mount(mount_b)
	_check(
		delayed_session != null
			and delayed_session.salvo_active
			and delayed_session.current_salvo.salvo_seed == first_seed,
		"delayed turret remains in the same grouping window and shared bias"
	)
	fire_control.get_shell_deviation_radians(mount_b, 0, 1)
	for _frame in 20:
		fire_control.update(shooter, target, mounts)
	_check(
		fire_control.get_debug_snapshots()[0].salvo_index == 0,
		"lead refresh never advances salvo index"
	)
	var second := fire_control.begin_salvo(&"destroyer_cannon")
	_check(
		second != null and second.salvo_index == 1
			and second.salvo_seed != first_seed,
		"next explicit post-reload salvo advances once and changes shared bias"
	)
	var repeated_begin := fire_control.begin_salvo(&"destroyer_cannon")
	_check(
		repeated_begin == second
			and fire_control.get_debug_snapshots()[0].salvo_index == 1,
		"repeated begin during active salvo does not advance index"
	)
	_arena.queue_free()
	await process_frame
	print("GUNNERY_SALVO_INDEX_LIFECYCLE_TEST failures=%d" % _failures.size())
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
	push_error("GUNNERY SALVO LIFECYCLE: %s" % label)
