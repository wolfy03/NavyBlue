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
	var first_target := _spawn_ship(&"ally", Vector3(0.0, 0.0, 3500.0))
	var second_target := _spawn_ship(&"ally", Vector3(1000.0, 0.0, 3500.0))
	await physics_frame
	shooter.combat.set_ai_engagement_target(first_target)
	for _frame in 4:
		await physics_frame
	var fire_control := shooter.combat.get_ai_fire_control()
	_check(fire_control != null, "AI target creates fire control")
	if fire_control != null:
		fire_control.tracking.correction_level = 0.65
		var command_before := fire_control.fire_command_id
		var reset_before := _reset_count(fire_control)
		for _index in 100:
			shooter.combat.set_ai_engagement_target(first_target)
		_check(
			fire_control.fire_command_id == command_before
				and _reset_count(fire_control) == reset_before
				and is_equal_approx(
					fire_control.tracking.correction_level, 0.65
				),
			"same target assignment preserves command, reset count, and correction"
		)
		shooter.combat.set_ai_engagement_target(second_target)
		_check(
			fire_control.fire_command_id == command_before + 1
				and fire_control.is_tracking_target(second_target)
				and is_zero_approx(fire_control.tracking.correction_level),
			"new target starts one new fire command and resets tracking"
		)
		var manual := ShipManualAimCommand.new()
		manual.local_azimuth_rad = 0.2
		manual.range_m = 3000.0
		shooter.combat.apply_manual_aim_command(manual)
		_check(
			fire_control.tracking.target_instance_id == 0,
			"player manual aim clears AI tracking state"
		)
	_arena.queue_free()
	await process_frame
	print("AI_GUNNERY_SAME_TARGET_ASSIGNMENT_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _reset_count(fire_control: ShipGunneryFireControl) -> int:
	var snapshots := fire_control.get_debug_snapshots()
	return snapshots[0].tracking_state_reset_count \
		if not snapshots.is_empty() else -1


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
	push_error("AI GUNNERY SAME TARGET: %s" % label)
