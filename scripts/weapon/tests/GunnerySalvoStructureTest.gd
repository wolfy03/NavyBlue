extends SceneTree
## Covers: shared salvo bias vs per-shell dispersion separation, salvo-index
## driven pattern changes, and fire-control aim stability (no per-frame jitter
## while a salvo is pending).

const NORMAL: AIGunneryDifficultyProfile = preload(
	"res://resources/ai_difficulty/gunnery_normal.tres"
)
const WEAPON_PROFILE: GunneryWeaponAccuracyProfile = preload(
	"res://resources/weapon_accuracy/default_cannon_accuracy.tres"
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
	_test_shared_bias_and_independent_dispersion()
	_test_salvo_index_changes_pattern()
	await _test_fire_control_aim_stability()
	print("GUNNERY_SALVO_STRUCTURE_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _make_context(salvo_index: int) -> GunneryAccuracyContext:
	var context := GunneryAccuracyContext.new()
	context.shooter_instance_id = 31
	context.target_instance_id = 32
	context.fire_command_id = 2
	context.salvo_index = salvo_index
	context.weapon_group_id = &"salvo_test_cannon"
	context.launch_position = Vector3.ZERO
	context.ideal_aim_point = Vector3(0, 0, 6000)
	context.range_m = 6000.0
	context.weapon_accuracy_profile = WEAPON_PROFILE
	context.difficulty_profile = NORMAL
	context.crew_stats = GunneryCrewStats.new()
	return context


func _test_shared_bias_and_independent_dispersion() -> void:
	var context := _make_context(0)
	var solution := GunneryAccuracyResolver.create_salvo_solution(context)
	var points: Array[Vector3] = []
	var biases: Array[Vector3] = []
	for shell_index in 4:
		var shell := GunneryAccuracyResolver.resolve_shell_point(
			solution, context, shell_index
		)
		points.append(shell.actual_aim_point)
		biases.append(shell.salvo_bias_offset)
	var shared_bias := true
	for bias in biases:
		if not bias.is_equal_approx(biases[0]):
			shared_bias = false
	_check(shared_bias, "salvo: every shell shares one salvo bias")
	var dispersion_differs := false
	for index in range(1, points.size()):
		if not points[index].is_equal_approx(points[0]):
			dispersion_differs = true
	_check(
		dispersion_differs,
		"salvo: shells do not aim at one identical point"
	)
	var max_distance := 0.0
	for point in points:
		max_distance = maxf(
			max_distance,
			point.distance_to(solution.biased_salvo_center)
		)
	_check(
		max_distance
			<= solution.shell_dispersion_sigma_m
				* GunneryAccuracyResolver.GAUSSIAN_CLAMP_SIGMAS * sqrt(2.0)
				+ 0.01,
		"salvo: dispersion stays inside the clamped gaussian envelope"
	)


func _test_salvo_index_changes_pattern() -> void:
	var first := GunneryAccuracyResolver.create_salvo_solution(_make_context(0))
	var second := GunneryAccuracyResolver.create_salvo_solution(_make_context(1))
	_check(
		not first.biased_salvo_center.is_equal_approx(
			second.biased_salvo_center
		),
		"salvo index: consecutive salvos land a different group center"
	)
	var turret_a := GunneryAccuracyResolver.make_shell_seed(
		first.salvo_seed, 0, 0
	)
	var turret_b := GunneryAccuracyResolver.make_shell_seed(
		first.salvo_seed, 1, 0
	)
	_check(turret_a != turret_b, "salvo index: turret index changes shell seed")


func _test_fire_control_aim_stability() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	var shooter := _spawn_ship("dd_bluewind", &"enemy", Vector3.ZERO)
	var target := _spawn_ship("dd_bluewind", &"ally", Vector3(0, 0, 4000))
	var mount_a := _spawn_mount("destroyer_cannon", Vector3(0, 2, 10))
	var mount_b := _spawn_mount("destroyer_cannon", Vector3(0, 2, -10))
	await physics_frame
	var mounts: Array[WeaponMount] = [mount_a, mount_b]
	var fire_control := ShipGunneryFireControl.new()
	fire_control.configure(NORMAL, GunneryCrewStats.new(), null)
	fire_control.update(shooter, target, mounts)
	var initial_point := fire_control.get_aim_point_for_mount(
		mount_a, target.global_position
	)
	_check(
		fire_control.has_solution_for_mount(mount_a),
		"stability: fire control solves for an in-range target"
	)
	_check(
		mount_a.get_instance_id() != mount_b.get_instance_id()
			and fire_control.get_aim_point_for_mount(
				mount_b, target.global_position
			).is_equal_approx(initial_point),
		"stability: same weapon group shares one aim point"
	)
	# No jitter: updates inside the refresh window keep the aim identical.
	var stable := true
	for _frame in 5:
		fire_control.update(shooter, target, mounts)
		if not fire_control.get_aim_point_for_mount(
			mount_a, target.global_position
		).is_equal_approx(initial_point):
			stable = false
	_check(stable, "stability: aim point does not jitter between refreshes")
	# Marking the salvo as fired and passing the refresh window rolls a new
	# salvo bias for the next salvo.
	fire_control.get_shell_deviation_radians(mount_a, 0, 1)
	var refresh_frames := 1 + maxi(1, roundi(
		NORMAL.aim_solution_refresh_interval_sec
		* float(Engine.physics_ticks_per_second)
	))
	for _frame in refresh_frames:
		fire_control.update(shooter, target, mounts)
	var snapshots := fire_control.get_debug_snapshots()
	_check(
		snapshots.size() == 1 and snapshots[0].salvo_index == 1,
		"stability: firing advances the salvo index"
	)
	var deviation_a := fire_control.get_shell_deviation_radians(mount_a, 0, 1)
	var deviation_b := fire_control.get_shell_deviation_radians(mount_a, 1, 1)
	_check(
		deviation_a != deviation_b,
		"stability: shells in one salvo receive different deviations"
	)
	_arena.queue_free()
	await process_frame


func _spawn_ship(
		ship_id: String,
		team: StringName,
		position: Vector3
) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	var source_data := _ship_database.get_ship(ship_id)
	ship.setup(source_data.duplicate(true) as ShipData, team, false, Color.WHITE)
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
		&"enemy"
	)
	mount.global_position = position
	return mount


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("GUNNERY SALVO: %s" % label)
