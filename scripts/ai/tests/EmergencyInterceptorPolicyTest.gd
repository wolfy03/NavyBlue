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
	var carrier := _spawn_ship(parent, "cv_seabastion", &"ally", services)
	var destroyer_a := _spawn_ship(parent, "dd_bluewind", &"ally", services)
	var destroyer_b := _spawn_ship(parent, "dd_bluewind", &"ally", services)
	var cruiser := _spawn_ship(parent, "cl_tidebreaker", &"ally", services)
	var threat := _spawn_ship(parent, "dd_bluewind", &"enemy", services)
	await process_frame
	var contexts: Array[FleetMemberContext] = []
	for ship in [carrier, destroyer_a, destroyer_b, cruiser]:
		ship.set_physics_process(false)
		contexts.append(FleetMemberContext.new().setup(ship))
	contexts[1].tactical_role = FleetMemberContext.TacticalRole.SCREEN
	contexts[2].tactical_role = FleetMemberContext.TacticalRole.FLANKER
	contexts[3].tactical_role = FleetMemberContext.TacticalRole.ESCORT
	var threat_context := FleetThreatContext.new().setup(
		threat,
		45.0,
		&"test_threat",
		0.0,
		6.0
	)
	var policy := EmergencyInterceptorPolicy.new()
	var assignments := policy.assign(
		contexts,
		[threat_context],
		carrier
	)
	var selected_ids: Dictionary = {}
	var selected_count := 0
	for assignment in assignments:
		_check(assignment.threat == threat, "assignment keeps typed threat")
		for interceptor in assignment.interceptors:
			selected_count += 1
			selected_ids[interceptor.get_instance_id()] = true
			_check(
				interceptor.ship_data.ship_class in [
					ShipData.ShipClass.DESTROYER,
					ShipData.ShipClass.CRUISER,
				],
				"only eligible escorts intercept"
			)
	_check(
		selected_count == 2 and selected_ids.size() == selected_count,
		"carrier threat gets two non-duplicate interceptors"
	)
	parent.queue_free()
	await process_frame
	print("EMERGENCY_INTERCEPTOR_POLICY_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _spawn_ship(
		parent: Node,
		ship_id: String,
		team: StringName,
		services: BattleServices
) -> ShipUnit:
	var ship := SHIP_SCENE.instantiate() as ShipUnit
	ship.setup(
		_database.get_ship(ship_id),
		team,
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
	push_error("EMERGENCY INTERCEPTOR POLICY: %s" % label)
