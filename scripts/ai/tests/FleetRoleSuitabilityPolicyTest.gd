extends SceneTree

const SHIP_SCENE: PackedScene = preload("res://scenes/unit/ship.tscn")

var _failures := PackedStringArray()
var _database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleTestServices.create(self)
	var parent := Node3D.new()
	root.add_child(parent)
	var cruiser := _spawn_ship(parent, "cl_tidebreaker", services)
	await process_frame
	cruiser.set_physics_process(false)
	var context := FleetMemberContext.new().setup(cruiser)
	context.tactical_role = FleetMemberContext.TacticalRole.ESCORT
	var policy := FleetRoleSuitabilityPolicy.new()
	var settings := FleetAISettings.new()
	var difficulty := AIDifficultyProfile.new()
	var unpreserved := policy.evaluate(
		context,
		FleetMemberContext.TacticalRole.ESCORT,
		cruiser,
		false,
		settings,
		difficulty
	)
	var preserved := policy.evaluate(
		context,
		FleetMemberContext.TacticalRole.ESCORT,
		cruiser,
		true,
		settings,
		difficulty
	)
	_check(
		unpreserved.suitable
			and is_equal_approx(preserved.score - unpreserved.score, 18.0),
		"existing role hold bonus is preserved"
	)
	var assignment := policy.select_best(
		[context],
		FleetMemberContext.TacticalRole.ESCORT,
		cruiser,
		true,
		settings,
		difficulty
	)
	_check(
		assignment.ship == cruiser
			and assignment.role == FleetMemberContext.TacticalRole.ESCORT,
		"typed role assignment selects the candidate"
	)
	parent.queue_free()
	await process_frame
	print("FLEET_ROLE_SUITABILITY_POLICY_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _spawn_ship(
		parent: Node,
		ship_id: String,
		services: BattleServices
) -> ShipUnit:
	var ship := SHIP_SCENE.instantiate() as ShipUnit
	ship.setup(
		_database.get_ship(ship_id),
		&"ally",
		false,
		Color.WHITE,
		null,
		{},
		services
	)
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	parent.add_child(ship)
	return ship


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("FLEET ROLE SUITABILITY: %s" % label)
