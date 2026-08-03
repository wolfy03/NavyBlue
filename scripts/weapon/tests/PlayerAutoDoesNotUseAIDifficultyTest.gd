extends SceneTree

var _failures := PackedStringArray()
var _arena: Node3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var ship := preload("res://scenes/unit/ship.tscn").instantiate() as ShipUnit
	ship.setup(
		ShipDatabase.new().get_ship("dd_bluewind").duplicate(true) as ShipData,
		&"player",
		true,
		Color.WHITE
	)
	_arena.add_child(ship)
	await physics_frame
	ship.combat.set_aim_point(Vector3(500.0, 0.0, 3000.0))
	# PLAYER_AUTO is reserved for a future player-owned fire-control model. It
	# deliberately does not opt into AI difficulty or crew error today.
	ship.combat.aim_source = ShipCombat.AimSource.PLAYER_AUTO
	for _frame in 3:
		await physics_frame
	_check(
		ship.combat.get_ai_fire_control() == null,
		"PLAYER_AUTO does not create AI fire control"
	)
	var providers_clear := true
	for mount in ship.combat.get_weapons_by_type(WeaponTypes.Type.CANNON):
		if (mount as CannonMount).shell_deviation_provider != null:
			providers_clear = false
	_check(providers_clear, "PLAYER_AUTO has no AI deviation provider")
	_arena.queue_free()
	await process_frame
	print("PLAYER_AUTO_DOES_NOT_USE_AI_DIFFICULTY_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("PLAYER AUTO POLICY: %s" % label)
