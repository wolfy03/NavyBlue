extends SceneTree

const SIMULATION_FRAMES := 36000

var _failures: Array[String] = []
var _provider_units: Array = []
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _ship_database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	arena.add_child(projectiles)
	var bounds := BattlefieldBounds.new()
	arena.add_child(bounds)
	var fleet_a := FleetAIController.new()
	var fleet_b := FleetAIController.new()
	arena.add_child(fleet_a)
	arena.add_child(fleet_b)
	fleet_a.setup(&"ten_a", &"ally", Callable(self, &"_get_provider_units"), bounds)
	fleet_b.setup(&"ten_b", &"enemy", Callable(self, &"_get_provider_units"), bounds)

	var composition := [
		"bb_ironwake",
		"bb_ironwake",
		"cl_tidebreaker",
		"cl_tidebreaker",
		"cv_seabastion",
		"dd_bluewind",
		"dd_bluewind",
		"dd_bluewind",
		"dd_bluewind",
		"dd_bluewind",
	]
	var members_a: Array[ShipUnit] = []
	var members_b: Array[ShipUnit] = []
	for index in composition.size():
		var row := float(index / 5)
		var column := float(index % 5)
		var member_a := _spawn_ship(
			arena,
			composition[index],
			&"ally",
			Vector3(-4200.0 + column * 420.0, 0.0, -900.0 + row * 850.0),
			0.0
		)
		var member_b := _spawn_ship(
			arena,
			composition[index],
			&"enemy",
			Vector3(4200.0 - column * 420.0, 0.0, -900.0 + row * 850.0),
			180.0
		)
		members_a.append(member_a)
		members_b.append(member_b)
	_provider_units.assign(members_a)
	_provider_units.append_array(members_b)
	for member in members_a:
		member.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
		fleet_a.register_member(member)
	for member in members_b:
		member.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
		fleet_b.register_member(member)

	var started_msec := Time.get_ticks_msec()
	for _frame in SIMULATION_FRAMES:
		await physics_frame
	var elapsed_sec := maxf(
		float(Time.get_ticks_msec() - started_msec) * 0.001,
		0.001
	)
	var average_processing_fps := float(SIMULATION_FRAMES) / elapsed_sec

	fleet_a.assignment_tracker.cleanup()
	fleet_b.assignment_tracker.cleanup()
	var all_members: Array[ShipUnit] = []
	all_members.append_array(fleet_a.get_alive_members())
	all_members.append_array(fleet_b.get_alive_members())
	var maximum_target_evaluations := 0
	var maximum_path_calculations := 0
	var maximum_target_changes := 0
	var maximum_tactical_updates := 0
	var maximum_pursuit_updates := 0
	var maximum_path_ship := ""
	for member in all_members:
		maximum_target_evaluations = maxi(
			maximum_target_evaluations,
			member.targeting.target_evaluation_count
		)
		if member.navigation.path_calculation_count > maximum_path_calculations:
			maximum_path_calculations = member.navigation.path_calculation_count
			maximum_path_ship = member.name
		maximum_target_changes = maxi(
			maximum_target_changes,
			member.targeting.target_change_count
		)
		maximum_tactical_updates = maxi(
			maximum_tactical_updates,
			member.ai.tactical_navigation_update_count
		)
		maximum_pursuit_updates = maxi(
			maximum_pursuit_updates,
			member.ai.pursuit_navigation_update_count
		)
		if member.get_ai_target() != member.ai.target \
				or member.get_ai_target() != member.combat.target:
			_failures.append("%s has inconsistent target ownership" % member.name)
		if not bounds.is_inside_bounds(member.global_position):
			_failures.append("%s remained outside the battlefield boundary" % member.name)
	if maximum_target_evaluations > 850:
		_failures.append("individual targeting exceeded the expected ~1 Hz budget")
	if maximum_path_calculations > 2200:
		_failures.append("navigation calculations exceeded the emergency cooldown ceiling")
	if maximum_target_changes > 100:
		_failures.append("a ship repeatedly oscillated between targets")
	if maximum_tactical_updates > 350:
		_failures.append("tactical navigation was refreshed too frequently")
	if fleet_a.assignment_tracker.cleanup_count > 650 \
			or fleet_b.assignment_tracker.cleanup_count > 650:
		_failures.append("fleet tracker cleanup exceeded its centralized interval budget")
	if fleet_a.assignment_tracker.get_assignment_count() > fleet_a.get_alive_members().size() \
			or fleet_b.assignment_tracker.get_assignment_count() > fleet_b.get_alive_members().size():
		_failures.append("destroyed ships left stale target assignments")
	if _fleet_spread_m(fleet_a.get_alive_members()) < 400.0 \
			or _fleet_spread_m(fleet_b.get_alive_members()) < 400.0:
		_failures.append("a fleet collapsed into one tactical point")

	print(
		"FLEET_AI_10V10 frames=%d elapsed_sec=%.2f processing_fps=%.1f live=%d fleet_eval=%d/%d cleanup=%d/%d max_target_eval=%d max_path=%d(%s) max_pursuit=%d max_target_changes=%d max_tactical_nav=%d failures=%d" % [
			SIMULATION_FRAMES,
			elapsed_sec,
			average_processing_fps,
			all_members.size(),
			fleet_a.fleet_evaluation_count,
			fleet_b.fleet_evaluation_count,
			fleet_a.assignment_tracker.cleanup_count,
			fleet_b.assignment_tracker.cleanup_count,
			maximum_target_evaluations,
			maximum_path_calculations,
			maximum_path_ship,
			maximum_pursuit_updates,
			maximum_target_changes,
			maximum_tactical_updates,
			_failures.size(),
		]
	)
	for failure in _failures:
		push_error("FLEET AI 10V10: %s" % failure)

	if root.has_node("ObjectPool"):
		root.get_node("ObjectPool").call(&"clear_pool")
	arena.queue_free()
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _spawn_ship(
		parent: Node3D,
		ship_id: String,
		team: StringName,
		position: Vector3,
		yaw_degrees: float
) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	var source_data := _ship_database.get_ship(ship_id)
	ship.setup(source_data.duplicate(true) as ShipData, team, false, Color.WHITE)
	parent.add_child(ship)
	ship.global_position = position
	ship.rotation.y = deg_to_rad(yaw_degrees)
	ship.health.debug_damage_log = false
	return ship


func _get_provider_units() -> Array:
	var result: Array = []
	for ship in _provider_units:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			result.append(ship)
	return result


func _fleet_spread_m(members: Array[ShipUnit]) -> float:
	if members.size() < 2:
		return 0.0
	var center := Vector3.ZERO
	for member in members:
		center += member.global_position
	center /= float(members.size())
	var maximum_distance := 0.0
	for member in members:
		maximum_distance = maxf(
			maximum_distance,
			member.global_position.distance_to(center)
		)
	return maximum_distance
