extends SceneTree

var _failures := PackedStringArray()
var _arena: Node3D
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _ship_database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var shooter := _spawn_ship(&"enemy", Vector3.ZERO)
	var target := _spawn_ship(&"ally", Vector3(0.0, 0.0, 4000.0))
	await physics_frame
	var fire_control := ShipGunneryFireControl.new()
	fire_control.configure(
		preload("res://resources/ai_difficulty/gunnery_normal.tres"),
		GunneryCrewStats.new()
	)
	var mounts := shooter.combat.get_weapons_by_type(WeaponTypes.Type.CANNON)
	target.velocity = Vector3(4.0, 0.0, 0.0)
	fire_control.update(shooter, target, mounts)
	fire_control.tracking.confidence = 0.9
	fire_control.tracking.correction_level = 0.8
	target.velocity = Vector3(-12.0, 0.0, 0.0)
	for _frame in 20:
		fire_control.update(shooter, target, mounts)
	_check(
		fire_control.tracking.confidence < 0.9,
		"sharp target maneuver reduces tracking confidence"
	)
	_check(
		fire_control.tracking.correction_level < 0.8,
		"sharp target maneuver partially resets accumulated correction"
	)
	_arena.queue_free()
	await process_frame
	print(
		"GUNNERY_TRACKING_CONFIDENCE_DROP_ON_MANEUVER_TEST failures=%d"
		% _failures.size()
	)
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


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("GUNNERY TRACKING MANEUVER: %s" % label)
