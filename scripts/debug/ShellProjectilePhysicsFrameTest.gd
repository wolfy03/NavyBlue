extends Node3D

const TEST_TIME_SCALE := 20.0
const TEST_TIMEOUT_SECONDS := 60.0

var _failures: Array[String] = []
var _last_fired_projectile: Node
var _water_impact_count := 0
var _last_water_impact_position := Vector3.ZERO
var _original_time_scale := 1.0
var _ocean_interaction: Node


func _ready() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_original_time_scale = Engine.time_scale
	Engine.time_scale = TEST_TIME_SCALE
	var weapon := WeaponDatabase.new().get_weapon("destroyer_cannon")
	_check(weapon != null, "destroyer cannon resource loads")
	if weapon == null or weapon.mount_scene == null:
		_finish()
		return
	var mount := weapon.mount_scene.instantiate() as CannonMount
	_check(mount != null, "actual cannon mount scene instantiates")
	if mount == null:
		_finish()
		return
	add_child(mount)
	var battle_services := BattleTestServices.create(get_tree())
	mount.setup(
		weapon,
		null,
		null,
		&"physics_frame_test",
		battle_services
	)
	mount.fired.connect(_on_mount_fired)
	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.projectile_water_impact.connect(_on_water_impact)
	await get_tree().process_frame
	_ocean_interaction = get_tree().get_first_node_in_group(
		&"ocean_interaction"
	)
	_check(
		_ocean_interaction != null,
		"physics-frame integration scene contains OceanInteraction"
	)

	for requested_distance in _get_test_distances(weapon.range_meters):
		await _run_distance_case(mount, weapon, requested_distance)

	if event_bus != null \
			and event_bus.projectile_water_impact.is_connected(
				_on_water_impact
			):
		event_bus.projectile_water_impact.disconnect(_on_water_impact)
	mount.queue_free()
	var object_pool := get_node_or_null("/root/ObjectPool")
	if object_pool != null:
		object_pool.clear_pool()
	await get_tree().process_frame
	await get_tree().process_frame
	_finish()


func _run_distance_case(
		mount: CannonMount,
		weapon: WeaponData,
		requested_distance: float
) -> void:
	_last_fired_projectile = null
	_water_impact_count = 0
	_last_water_impact_position = Vector3.ZERO
	mount.reload_left = 0.0
	var aim_point := Vector3(0.0, 0.0, -requested_distance)
	mount.aim_at(aim_point)
	mount.call(&"_turn_toward", aim_point, 100.0)
	mount.call(&"_physics_process", 0.0)
	mount.call(&"_turn_toward", aim_point, 100.0)
	mount.call(&"_physics_process", 0.0)
	var readiness := mount.get_fire_readiness_at(aim_point)

	if requested_distance > weapon.range_meters:
		_check(
			readiness == WeaponFireReadiness.State.OUT_OF_RANGE
				or readiness
					== WeaponFireReadiness.State.NO_BALLISTIC_SOLUTION,
			"physics-frame test rejects configured range + 100 m"
		)
		print(
			"[ShellPhysicsFrame] target=%.1f status=OUT_OF_RANGE"
			% requested_distance
		)
		return

	_check(
		readiness == WeaponFireReadiness.State.READY,
		"actual cannon is ready at %.0f m" % requested_distance
	)
	if readiness != WeaponFireReadiness.State.READY:
		return
	var fired := mount.fire()
	_check(fired, "actual cannon fires at %.0f m" % requested_distance)
	var shell := _last_fired_projectile as ShellProjectile
	_check(shell != null, "actual cannon emits a ShellProjectile")
	if shell == null:
		return
	_check(
		not str(shell.get_meta("pool_key", "")).is_empty(),
		"actual shell is spawned through ObjectPool"
	)
	var launch_origin := shell.global_position
	var elapsed_seconds := 0.0
	while shell.active and elapsed_seconds < TEST_TIMEOUT_SECONDS:
		await get_tree().physics_frame
		elapsed_seconds += get_physics_process_delta_time()
	var actual_distance := CombatGeometryXZ.distance_xz(
		launch_origin,
		_last_water_impact_position
	)
	var target_distance := CombatGeometryXZ.distance_xz(
		launch_origin,
		aim_point
	)
	var error_m := absf(actual_distance - target_distance)
	var allowed_ratio := 0.02 \
		if requested_distance >= weapon.range_meters * 0.9 else 0.01
	_check(
		not shell.active,
		"actual shell finishes before the physics-frame timeout"
	)
	_check(
		shell.last_despawn_reason == Projectile.DespawnReason.WATER_IMPACT,
		"actual shell reaches water at %.0f m" % requested_distance
	)
	_check(
		_water_impact_count == 1,
		"actual shell emits one water impact at %.0f m" % requested_distance
	)
	var pool_state_after := _get_pool_state()
	_check(
		int(pool_state_after.get("active_splashes", 0)) > 0,
		"physics-frame impact activates a real splash at %.0f m"
			% requested_distance
	)
	_check(
		error_m <= requested_distance * allowed_ratio,
		"physics-frame error stays within %.0f%% at %.0f m" % [
			allowed_ratio * 100.0,
			requested_distance,
		]
	)
	print(
		(
			"[ShellPhysicsFrame] target=%.1f actual=%.1f error=%.2f "
			+ "flight=%.2f reason=%s water_impacts=%d"
		) % [
			requested_distance,
			actual_distance,
			error_m,
			elapsed_seconds,
			Projectile.DespawnReason.keys()[shell.last_despawn_reason],
			_water_impact_count,
		]
	)


func _get_test_distances(configured_range_m: float) -> Array[float]:
	return [
		1000.0,
		3000.0,
		5000.0,
		configured_range_m * 0.9,
		configured_range_m,
		configured_range_m + 100.0,
	]


func _on_mount_fired(projectile: Node) -> void:
	_last_fired_projectile = projectile


func _on_water_impact(position: Vector3, _strength: float) -> void:
	_water_impact_count += 1
	_last_water_impact_position = position


func _get_pool_state() -> Dictionary:
	if _ocean_interaction == null \
			or not is_instance_valid(_ocean_interaction) \
			or not _ocean_interaction.has_method(&"get_pool_debug_state"):
		return {}
	return _ocean_interaction.call(&"get_pool_debug_state") as Dictionary


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	Engine.time_scale = _original_time_scale
	for failure in _failures:
		push_error("SHELL PHYSICS-FRAME TEST: %s" % failure)
	if _failures.is_empty():
		print("SHELL_PROJECTILE_PHYSICS_FRAME_TEST PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
