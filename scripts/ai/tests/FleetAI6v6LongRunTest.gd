extends SceneTree

const DEFAULT_SIMULATION_FRAMES := 36000
const SAMPLE_INTERVAL_FRAMES := 60

var _failures: Array[String] = []
var _provider_units: Array = []
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _ship_database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var simulation_frames := _resolve_simulation_frames()
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
	fleet_a.setup(&"six_a", &"ally", Callable(self, &"_get_provider_units"), bounds)
	fleet_b.setup(&"six_b", &"enemy", Callable(self, &"_get_provider_units"), bounds)

	var composition := [
		"cv_seabastion",
		"bb_ironwake",
		"cl_tidebreaker",
		"cl_tidebreaker",
		"dd_bluewind",
		"dd_bluewind",
	]
	var members_a: Array[ShipUnit] = []
	var members_b: Array[ShipUnit] = []
	for index in composition.size():
		var row := float(index / 3)
		var column := float(index % 3)
		var member_a := _spawn_ship(
			arena,
			composition[index],
			&"ally",
			Vector3(-4200.0 + column * 500.0, 0.0, -700.0 + row * 800.0),
			-90.0
		)
		var member_b := _spawn_ship(
			arena,
			composition[index],
			&"enemy",
			Vector3(4200.0 - column * 500.0, 0.0, -700.0 + row * 800.0),
			90.0
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

	var metrics := {
		"max_live": 0,
		"max_interceptors": 0,
		"max_target_evaluations": 0,
		"max_target_changes": 0,
		"max_path_calculations": 0,
		"max_tactical_navigation_updates": 0,
		"max_fleet_spread_m": 0.0,
		"boundary_violations": 0,
		"target_ownership_failures": 0,
	}
	var started_msec := Time.get_ticks_msec()
	for frame in simulation_frames:
		await physics_frame
		if frame % SAMPLE_INTERVAL_FRAMES == 0 or frame == simulation_frames - 1:
			_sample_metrics(metrics, bounds, fleet_a, fleet_b)
	var elapsed_sec := maxf(float(Time.get_ticks_msec() - started_msec) * 0.001, 0.001)
	var average_processing_fps := float(simulation_frames) / elapsed_sec

	var path_limit := maxi(80, int(ceil(float(simulation_frames) / 15.0)))
	var target_change_limit := maxi(15, int(ceil(float(simulation_frames) / 300.0)))
	var tactical_navigation_limit := maxi(25, int(ceil(float(simulation_frames) / 90.0)))
	if int(metrics["max_path_calculations"]) > path_limit:
		_failures.append("navigation path calculations exceeded the stability budget")
	if int(metrics["max_target_changes"]) > target_change_limit:
		_failures.append("an individual ship repeatedly oscillated between targets")
	if int(metrics["max_tactical_navigation_updates"]) > tactical_navigation_limit:
		_failures.append("tactical navigation targets were refreshed too frequently")
	if int(metrics["max_interceptors"]) > 6:
		_failures.append("more than three interceptors were assigned per fleet")
	if int(metrics["boundary_violations"]) > 0:
		_failures.append("one or more ships remained outside battlefield bounds")
	if int(metrics["target_ownership_failures"]) > 0:
		_failures.append("target ownership diverged between targeting, AI, and combat")
	if fleet_a.role_change_count + fleet_b.role_change_count \
			> maxi(40, int(ceil(float(simulation_frames) / 120.0))):
		_failures.append("fleet tactical roles changed too frequently")

	print(
		"FLEET_AI_6V6 frames=%d elapsed_sec=%.2f processing_fps=%.1f live_peak=%d fleet_eval=%d/%d role_eval=%d/%d role_changes=%d/%d primary_changes=%d/%d tactical_updates=%d/%d max_interceptors=%d max_target_eval=%d max_target_changes=%d max_path=%d max_tactical_nav=%d max_spread=%.1f boundary_violations=%d failures=%d" % [
			simulation_frames,
			elapsed_sec,
			average_processing_fps,
			int(metrics["max_live"]),
			fleet_a.fleet_evaluation_count,
			fleet_b.fleet_evaluation_count,
			fleet_a.role_evaluation_count,
			fleet_b.role_evaluation_count,
			fleet_a.role_change_count,
			fleet_b.role_change_count,
			fleet_a.target_change_count,
			fleet_b.target_change_count,
			fleet_a.tactical_position_update_count,
			fleet_b.tactical_position_update_count,
			int(metrics["max_interceptors"]),
			int(metrics["max_target_evaluations"]),
			int(metrics["max_target_changes"]),
			int(metrics["max_path_calculations"]),
			int(metrics["max_tactical_navigation_updates"]),
			float(metrics["max_fleet_spread_m"]),
			int(metrics["boundary_violations"]),
			_failures.size(),
		]
	)
	for failure in _failures:
		push_error("FLEET AI 6V6: %s" % failure)

	if root.has_node("ObjectPool"):
		root.get_node("ObjectPool").call(&"clear_pool")
	arena.queue_free()
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _sample_metrics(
		metrics: Dictionary,
		bounds: BattlefieldBounds,
		fleet_a: FleetAIController,
		fleet_b: FleetAIController
) -> void:
	var live_units := _get_provider_units()
	metrics["max_live"] = maxi(int(metrics["max_live"]), live_units.size())
	var interceptors := 0
	for fleet in [fleet_a, fleet_b]:
		for member in fleet.get_alive_members():
			var context: FleetMemberContext = fleet.get_member_context(member)
			if context != null \
					and context.tactical_role == FleetMemberContext.TacticalRole.INTERCEPT:
				interceptors += 1
		metrics["max_fleet_spread_m"] = maxf(
			float(metrics["max_fleet_spread_m"]),
			_fleet_spread_m(fleet.get_alive_members())
		)
	metrics["max_interceptors"] = maxi(int(metrics["max_interceptors"]), interceptors)
	for member_value in live_units:
		var member := member_value as ShipUnit
		if member == null:
			continue
		metrics["max_target_evaluations"] = maxi(
			int(metrics["max_target_evaluations"]),
			member.targeting.target_evaluation_count
		)
		metrics["max_target_changes"] = maxi(
			int(metrics["max_target_changes"]),
			member.targeting.target_change_count
		)
		metrics["max_path_calculations"] = maxi(
			int(metrics["max_path_calculations"]),
			member.navigation.path_calculation_count
		)
		metrics["max_tactical_navigation_updates"] = maxi(
			int(metrics["max_tactical_navigation_updates"]),
			member.ai.tactical_navigation_update_count
		)
		if member.get_ai_target() != member.ai.target \
				or member.get_ai_target() != member.combat.target:
			metrics["target_ownership_failures"] = int(
				metrics["target_ownership_failures"]
			) + 1
		if not bounds.is_inside_bounds(member.global_position):
			metrics["boundary_violations"] = int(metrics["boundary_violations"]) + 1


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


func _resolve_simulation_frames() -> int:
	var override := OS.get_environment("NAVYBLUE_LONG_RUN_FRAMES")
	return maxi(int(override), 1) if override.is_valid_int() else DEFAULT_SIMULATION_FRAMES
