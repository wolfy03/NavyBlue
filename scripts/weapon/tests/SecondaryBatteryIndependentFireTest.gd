extends SceneTree
## Covers independent secondary fire: no shared salvo, per-mount fire sequence,
## per-mount tracking/bias, shared weapon-group lead, and mixed reload and
## traverse speeds where a slow gun never holds up a fast one.

const SECONDARY_ACCURACY: GunneryWeaponAccuracyProfile = preload(
	"res://resources/weapon_accuracy/secondary_gun_accuracy.tres"
)
const NORMAL: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)

var _failures := PackedStringArray()
var _arena: Node3D
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _mount_scene := preload("res://scenes/weapon/mounts/cannon_mount.tscn")
var _ship_database := ShipDatabase.new()
var _weapon_database := WeaponDatabase.new()
var _fire_counts: Dictionary = {}
var _services: BattleServices


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_shared_lead_with_independent_bias()
	await _test_runtime_ballistics_split_groups()
	await _test_mixed_reload_times()
	await _test_mixed_traverse_times()
	await _test_no_shared_salvo_and_state_cleanup()
	print(
		"SECONDARY_BATTERY_INDEPENDENT_FIRE_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


#region Shared lead, independent error
func _test_shared_lead_with_independent_bias() -> void:
	_build_arena()
	var shooter := _spawn_ship("cl_tidebreaker", &"enemy", Vector3.ZERO)
	var target := _spawn_ship("dd_bluewind", &"ally", Vector3(0, 0, 3000))
	target.velocity = Vector3(12.0, 0.0, 0.0)
	var mount_a := _spawn_mount("naval_gun_100mm", Vector3(-20, 6, 10))
	var mount_b := _spawn_mount("naval_gun_100mm", Vector3(-20, 6, -10))
	await physics_frame
	var fire_control := ShipGunneryFireControl.new()
	fire_control.configure(NORMAL, GunneryCrewStats.new(), null, SECONDARY_ACCURACY)
	fire_control.set_fire_mode(
		ShipGunneryFireControl.FireMode.INDEPENDENT_MOUNT
	)
	var mounts: Array[WeaponMount] = [mount_a, mount_b]
	fire_control.update(shooter, target, mounts)
	var lead_a := fire_control.get_lead_point_for_mount(
		mount_a, target.global_position
	)
	var lead_b := fire_control.get_lead_point_for_mount(
		mount_b, target.global_position
	)
	_check(
		lead_a.is_equal_approx(lead_b),
		"same weapon group shares one ideal lead point"
	)
	_check(
		not lead_a.is_equal_approx(target.global_position),
		"the shared solution still leads the moving target"
	)
	var state_a := SecondaryMountFireControlState.create(mount_a)
	var state_b := SecondaryMountFireControlState.create(mount_b)
	var accuracy_a := fire_control.resolve_independent_mount_accuracy(
		mount_a, state_a.tracking_state, state_a.fire_sequence_index
	)
	var accuracy_b := fire_control.resolve_independent_mount_accuracy(
		mount_b, state_b.tracking_state, state_b.fire_sequence_index
	)
	_check(
		accuracy_a != null and accuracy_b != null,
		"both mounts resolve an independent aim"
	)
	if accuracy_a == null or accuracy_b == null:
		_teardown_arena()
		return
	_check(
		accuracy_a.ideal_aim_point.is_equal_approx(
			accuracy_b.ideal_aim_point
		),
		"independent mounts keep the same ideal aim point"
	)
	_check(
		not accuracy_a.actual_aim_point.is_equal_approx(
			accuracy_b.actual_aim_point
		),
		"each mount applies its own fire-control bias"
	)
	_check(
		not accuracy_a.salvo_bias_offset.is_equal_approx(
			accuracy_b.salvo_bias_offset
		),
		"the two mounts do not share one salvo bias"
	)
	# Correcting one gun must not move the other's aim.
	var b_aim_before := fire_control.get_aim_point_for_mount(
		mount_b, target.global_position
	)
	fire_control.advance_mount_correction(state_a.tracking_state)
	state_a.fire_sequence_index += 1
	fire_control.resolve_independent_mount_accuracy(
		mount_a, state_a.tracking_state, state_a.fire_sequence_index
	)
	var b_aim_after := fire_control.get_aim_point_for_mount(
		mount_b, target.global_position
	)
	_check(
		b_aim_before.is_equal_approx(b_aim_after),
		"one mount's correction never changes another mount's aim"
	)
	_check(
		state_b.tracking_state.correction_level == 0.0
			and state_a.tracking_state.correction_level > 0.0,
		"tracking correction stays private to the firing mount"
	)
	# Determinism: same mount, same sequence index -> same solution.
	var repeat_state := SecondaryMountFireControlState.create(mount_b)
	var repeat := fire_control.resolve_independent_mount_accuracy(
		mount_b, repeat_state.tracking_state, 0
	)
	_check(
		repeat != null
			and repeat.actual_aim_point.is_equal_approx(
				accuracy_b.actual_aim_point
			),
		"the per-mount seed is deterministic"
	)
	_teardown_arena()
#endregion


func _test_runtime_ballistics_split_groups() -> void:
	_build_arena()
	var shooter := _spawn_ship("cl_tidebreaker", &"enemy", Vector3.ZERO)
	var target := _spawn_ship("dd_bluewind", &"ally", Vector3(0, 0, 3000))
	target.velocity = Vector3(12.0, 0.0, 0.0)
	var standard := _spawn_mount(
		"naval_gun_100mm",
		Vector3(-20, 6, 10)
	)
	var upgraded := _spawn_mount(
		"naval_gun_100mm",
		Vector3(-20, 6, -10)
	)
	upgraded.runtime_stats.projectile_speed_multiplier = 1.2
	await physics_frame
	var fire_control := ShipGunneryFireControl.new()
	fire_control.configure(
		NORMAL,
		GunneryCrewStats.new(),
		null,
		SECONDARY_ACCURACY
	)
	fire_control.set_fire_mode(
		ShipGunneryFireControl.FireMode.INDEPENDENT_MOUNT
	)
	var mounts: Array[WeaponMount] = [standard, upgraded]
	fire_control.update(shooter, target, mounts)
	var standard_group := fire_control.get_group_session_for_mount(standard)
	var upgraded_group := fire_control.get_group_session_for_mount(upgraded)
	_check(
		standard_group != null and upgraded_group != null,
		"runtime ballistic variants both receive a weapon group"
	)
	if standard_group != null and upgraded_group != null:
		_check(
			standard_group != upgraded_group,
			"different runtime muzzle velocities do not share one lead solve"
		)
		_check(
			not is_equal_approx(
				standard_group.flight_time_sec,
				upgraded_group.flight_time_sec
			),
			"runtime ballistic groups preserve different flight times"
		)
	_teardown_arena()


#region Mixed reload
func _test_mixed_reload_times() -> void:
	_build_arena()
	# Same weapon, different runtime reload: 0.5x -> 4 s, 1.0x -> 8 s. Traverse
	# is made fast for both so reload is the only differing constraint.
	var controller := await _build_battery(
		[
			{"weapon": "naval_gun_100mm", "reload_multiplier": 0.5, "z": 20.0, "yaw": 240.0},
			{"weapon": "naval_gun_100mm", "reload_multiplier": 1.0, "z": -20.0, "yaw": 240.0},
		],
		"mixed_reload"
	)
	if controller == null:
		_teardown_arena()
		return
	var fast := controller.secondary_mounts[0]
	var slow := controller.secondary_mounts[1]
	await _run_battery(controller, 20.0)
	var fast_shots := int(_fire_counts.get(fast.get_instance_id(), 0))
	var slow_shots := int(_fire_counts.get(slow.get_instance_id(), 0))
	_check(
		fast_shots > 0 and slow_shots > 0,
		"both mounts fire during the engagement (fast=%d slow=%d)"
			% [fast_shots, slow_shots]
	)
	_check(
		fast_shots > slow_shots,
		"the 4 s gun outshoots the 8 s gun (fast=%d slow=%d)"
			% [fast_shots, slow_shots]
	)
	# A shared salvo would force both to one cadence; independent fire should
	# roughly track the reload ratio.
	_check(
		float(fast_shots) >= float(slow_shots) * 1.5,
		"shot ratio reflects the reload difference (fast=%d slow=%d)"
			% [fast_shots, slow_shots]
	)
	var snapshot := controller.get_debug_snapshot()
	_check(
		not snapshot.shared_salvo_active,
		"independent mode never opens a shared salvo"
	)
	_check(
		int(snapshot.mount_shots_fired.get(fast.get_instance_id(), 0))
			== fast_shots,
		"the debug snapshot reports per-mount shot counts"
	)
	_check(
		int(snapshot.mount_fire_sequence_indices.get(
			fast.get_instance_id(), -1
		)) == fast_shots,
		"each mount advances its own fire sequence"
	)
	_check(
		int(snapshot.mount_fire_sequence_indices.get(
			slow.get_instance_id(), -1
		)) != int(snapshot.mount_fire_sequence_indices.get(
			fast.get_instance_id(), -1
		)),
		"the two mounts hold different fire sequence indices"
	)
	_teardown_arena()
#endregion


#region Mixed traverse
func _test_mixed_traverse_times() -> void:
	_build_arena()
	# Both mounts start at rest facing -Z with the target at +Z, so each must
	# traverse 180 degrees. At 120 deg/s that takes 1.5 s; at 1.5 deg/s it
	# cannot finish inside the window.
	var controller := await _build_battery(
		[
			{"weapon": "naval_gun_100mm", "reload_multiplier": 0.5, "z": 20.0, "yaw": 120.0},
			{"weapon": "naval_gun_100mm", "reload_multiplier": 0.5, "z": -20.0, "yaw": 1.5},
		],
		"mixed_traverse"
	)
	if controller == null:
		_teardown_arena()
		return
	var quick := controller.secondary_mounts[0]
	var sluggish := controller.secondary_mounts[1]
	await _run_battery(controller, 6.0)
	var quick_shots := int(_fire_counts.get(quick.get_instance_id(), 0))
	var sluggish_shots := int(_fire_counts.get(sluggish.get_instance_id(), 0))
	_check(
		quick_shots > 0,
		"the fast-traversing gun fires once aligned (%d shots)" % quick_shots
	)
	_check(
		quick_shots > sluggish_shots,
		"a still-traversing gun does not gate the aligned one (quick=%d slow=%d)"
			% [quick_shots, sluggish_shots]
	)
	_teardown_arena()
#endregion


#region Salvo isolation and cleanup
func _test_no_shared_salvo_and_state_cleanup() -> void:
	_build_arena()
	var controller := await _build_battery(
		[
			{"weapon": "naval_gun_100mm", "reload_multiplier": 0.5, "z": 20.0, "yaw": 240.0},
			{"weapon": "naval_gun_100mm", "reload_multiplier": 0.5, "z": -20.0, "yaw": 240.0},
		],
		"cleanup"
	)
	if controller == null:
		_teardown_arena()
		return
	for mount in controller.secondary_mounts:
		_check(
			controller.get_mount_fire_control_state(mount) != null,
			"every configured mount owns a fire-control state before firing"
		)
	await _run_battery(controller, 6.0)
	var profile := controller.profile
	_check(
		profile.get_effective_fire_coordination_mode()
			== SecondaryBatteryProfile.FireCoordinationMode.INDEPENDENT,
		"the battery runs in INDEPENDENT coordination mode"
	)
	_check(
		controller.fire_control.fire_mode
			== ShipGunneryFireControl.FireMode.INDEPENDENT_MOUNT,
		"the shared fire control runs in INDEPENDENT_MOUNT mode"
	)
	var doomed := controller.secondary_mounts[0]
	var doomed_id := doomed.get_instance_id()
	_check(
		controller.get_mount_fire_control_state(doomed) != null,
		"a live mount owns a fire-control state"
	)
	var surviving := controller.secondary_mounts[1]
	var surviving_state := controller.get_mount_fire_control_state(surviving)
	var sequence_before_weapon_change := surviving_state.fire_sequence_index
	surviving.weapon_data = surviving.weapon_data.duplicate(true) as WeaponData
	controller.update(0.016)
	var rebound_state := controller.get_mount_fire_control_state(surviving)
	_check(
		rebound_state == surviving_state
			and rebound_state.fire_sequence_index
				== sequence_before_weapon_change
			and rebound_state.is_bound_to_weapon(surviving),
		"WeaponData replacement resets tracking without reusing the fire sequence"
	)
	doomed.queue_free()
	await physics_frame
	controller.update(0.016)
	_check(
		not controller.get_debug_snapshot()
			.mount_shots_fired.has(doomed_id),
		"a destroyed mount's fire-control state is released"
	)
	_teardown_arena()
#endregion


#region Harness
func _build_battery(
		specs: Array,
		label: String
) -> SecondaryBatteryController:
	var shooter := _spawn_ship("cl_tidebreaker", &"enemy", Vector3.ZERO)
	var target := _spawn_ship("dd_bluewind", &"ally", Vector3(0, 0, 2200))
	# Keep the geometry static so only readiness differs between mounts.
	shooter.set_physics_process(false)
	target.set_physics_process(false)
	var mounts: Array[CannonMount] = []
	for spec_value in specs:
		var spec := spec_value as Dictionary
		var mount := _spawn_mount(
			str(spec["weapon"]),
			Vector3(-24.0, 6.0, float(spec["z"]))
		)
		# Reload comes from weapon_data * runtime multiplier, so vary the
		# multiplier rather than the vestigial CannonMount.reload_seconds.
		if spec.has("reload_multiplier"):
			mount.runtime_stats.reload_multiplier = float(
				spec["reload_multiplier"]
			)
		if spec.has("yaw"):
			mount.yaw_speed = float(spec["yaw"])
		mount.fired.connect(_on_mount_fired.bind(mount.get_instance_id()))
		mounts.append(mount)
	await physics_frame
	var controller := SecondaryBatteryController.new()
	var ok := controller.setup(
		shooter,
		shooter.combat,
		mounts,
		null,
		Callable(self, "_provide_candidates").bind(target)
	)
	_check(ok, "%s: battery controller configures" % label)
	return controller if ok else null


## Steps the controller on a fixed timestep. Mount reload runs on the mounts'
## own _physics_process, so the arena advances in real physics frames.
func _run_battery(
		controller: SecondaryBatteryController,
		seconds: float
) -> void:
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	var frames := int(seconds / step)
	for _frame in frames:
		controller.update(step)
		await physics_frame


func _provide_candidates(target: ShipUnit) -> Array:
	if target == null or not is_instance_valid(target):
		return []
	return [target]


func _on_mount_fired(_projectile: Node, mount_id: int) -> void:
	_fire_counts[mount_id] = int(_fire_counts.get(mount_id, 0)) + 1


func _build_arena() -> void:
	_fire_counts.clear()
	# Mounts need an injected ProjectileFactory to actually launch a shell.
	_services = BattleTestServices.create(self)
	_arena = Node3D.new()
	root.add_child(_arena)
	var projectile_root := Node3D.new()
	projectile_root.name = "Projectiles"
	projectile_root.add_to_group(&"projectile_root")
	_arena.add_child(projectile_root)


func _teardown_arena() -> void:
	if _arena != null:
		# Match BattleScene shutdown ordering: return live projectiles while
		# their parent is still in a stable SceneTree, then remove the arena.
		# Letting SceneTree quit perform this step would make ObjectPool reparent
		# children while root is already busy removing them.
		for projectile_root in get_nodes_in_group(&"projectile_root"):
			if projectile_root == null \
					or not is_instance_valid(projectile_root) \
					or not _arena.is_ancestor_of(projectile_root):
				continue
			for child in projectile_root.get_children():
				var projectile := child as ProjectileBase
				if projectile != null:
					projectile.recycle_projectile()
					continue
				var rigid_projectile := child as WeaponProjectileBase
				if rigid_projectile != null:
					rigid_projectile.recycle_projectile()
		_arena.queue_free()
		_arena = null


func _spawn_ship(
		ship_id: String,
		team: StringName,
		position: Vector3
) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	var source_data := _ship_database.get_ship(ship_id)
	ship.setup(
		source_data.duplicate(true) as ShipData,
		team,
		false,
		Color.WHITE,
		null,
		{},
		_services
	)
	_arena.add_child(ship)
	ship.global_position = position
	return ship


func _spawn_mount(weapon_id: String, position: Vector3) -> CannonMount:
	var mount := _mount_scene.instantiate() as CannonMount
	_arena.add_child(mount)
	mount.setup(
		_weapon_database.get_weapon(weapon_id),
		null,
		null,
		&"enemy",
		_services
	)
	mount.global_position = position
	return mount


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("SECONDARY INDEPENDENT FIRE: %s" % label)
#endregion
