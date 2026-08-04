extends SceneTree
## Central-solution dive bombing: one solution per squadron anchored on a
## reference aircraft. Covers solution survival across the controller's
## internal reset (including a second attack pass), the fixed dive direction,
## reference selection/stability/replacement, the reference-based release
## window, squadron-wide real projectile release, and the safe skip that
## preserves ammunition when the window is never met.

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const GRAVITY := 9.8

var _failures: Array[String] = []
var _projectile_release_count := 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_resolver_release_interval_independence()
	_test_resolver_fixed_angle_velocity()
	await _test_controller_with_squadron()
	print(
		"DIVE_BOMB_CENTRAL_SOLUTION_TEST failures=%d" % _failures.size()
	)
	for failure in _failures:
		push_error("DIVE BOMB CENTRAL SOLUTION: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


#region Resolver contracts
func _make_dive_data() -> DiveBomberCombatData:
	var data := DiveBomberCombatData.new()
	data.dive_entry_altitude_m = 350.0
	data.dive_angle_degrees = 55.0
	data.dive_speed_mps = 210.0
	data.approach_distance_m = 900.0
	data.automatic_release_altitude_m = 90.0
	return data


## release_interval_sec staggers bombs inside one squadron; it must never
## shift the central ballistic solution.
func _test_resolver_release_interval_independence() -> void:
	var fast := AircraftWeaponData.new()
	fast.downward_release_speed_mps = 20.0
	fast.release_interval_sec = 0.0
	var slow := AircraftWeaponData.new()
	slow.downward_release_speed_mps = 20.0
	slow.release_interval_sec = 2.5
	var target_velocity := Vector3(9.0, 0.0, 0.0)
	var solution_fast := DiveBombAttackResolver.solve(
		Vector3(0, 350, -3000), Vector3.FORWARD, 140.0,
		Vector3.ZERO, target_velocity, 0.0,
		_make_dive_data(), fast, GRAVITY, Vector3(0, 0, 1)
	)
	var solution_slow := DiveBombAttackResolver.solve(
		Vector3(0, 350, -3000), Vector3.FORWARD, 140.0,
		Vector3.ZERO, target_velocity, 0.0,
		_make_dive_data(), slow, GRAVITY, Vector3(0, 0, 1)
	)
	_check(
		solution_fast.valid and solution_slow.valid,
		"interval: both solutions solve"
	)
	_check(
		solution_fast.predicted_impact_position.is_equal_approx(
			solution_slow.predicted_impact_position
		) and solution_fast.release_position.is_equal_approx(
			solution_slow.release_position
		),
		"interval: release_interval_sec never moves impact or release"
	)
	_check(
		is_zero_approx(solution_fast.release_delay_sec),
		"interval: no squadron stagger enters the ballistic timing"
	)


## The resolver's assumed bomb velocity must decompose exactly along the fixed
## dive angle contract that the flight code also uses.
func _test_resolver_fixed_angle_velocity() -> void:
	var weapon := AircraftWeaponData.new()
	weapon.downward_release_speed_mps = 20.0
	var solution := DiveBombAttackResolver.solve(
		Vector3(0, 350, -3000), Vector3.FORWARD, 140.0,
		Vector3.ZERO, Vector3.ZERO, 0.0,
		_make_dive_data(), weapon, GRAVITY, Vector3(0, 0, 1)
	)
	_check(solution.valid, "angle: solves")
	var angle_rad := deg_to_rad(55.0)
	var horizontal := Vector2(
		solution.predicted_bomb_velocity.x,
		solution.predicted_bomb_velocity.z
	).length()
	_check(
		absf(horizontal - 210.0 * cos(angle_rad)) < 0.01,
		"angle: bomb horizontal speed equals dive_speed * cos(angle)"
	)
	_check(
		absf(solution.predicted_bomb_velocity.y
			- (-210.0 * sin(angle_rad))) < 0.01,
		"angle: bomb vertical speed equals the dive descent rate"
	)
#endregion


func _test_controller_with_squadron() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	var carrier := battle.player_ship as ShipUnit
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null, "squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
		aircraft.weapon_controller.weapon_released.connect(
			_on_weapon_released
		)
	var controller := squadron.dive_bomb_controller
	var dive_data: DiveBomberCombatData = controller.dive_data
	var weapon_data: AircraftWeaponData = \
		squadron.squadron_data.aircraft_data.weapon_data

	# --- Reference selection: closest to formation center, not array order.
	var aircraft := squadron.get_alive_aircraft()
	squadron.formation_center = Vector3(0.0, 200.0, -600.0)
	squadron._formation_forward = Vector3(0.0, 0.0, 1.0)
	# Unambiguous spacing: aircraft[1] sits 10 m from the center, the rest are
	# hundreds of meters out, in an order unrelated to the array order.
	var center_offsets := [200.0, 10.0, -300.0, 420.0]
	for index in aircraft.size():
		aircraft[index].global_position = Vector3(
			center_offsets[index % center_offsets.size()],
			200.0,
			-600.0
		)
	var expected_reference := aircraft[1]
	var selected := squadron.select_dive_bomb_reference_aircraft()
	_check(
		selected == expected_reference,
		"reference: closest aircraft to formation center is selected"
	)

	# --- One solution drives the dive.
	var solution := DiveBombAttackResolver.solve_from_dive_entry(
		squadron.formation_center,
		Vector3(0, 0, 1),
		Vector3.ZERO,
		Vector3.ZERO,
		0.0,
		dive_data,
		weapon_data,
		GRAVITY,
		Vector3(0, 0, 1)
	)
	_check(solution.valid, "solution: dive-entry solve succeeds")
	var begin_result: int = controller.begin_dive_with_solution(
		solution,
		AircraftSquadron.DiveControlSource.PLAYER
	)
	_check(
		begin_result == DiveBombAttackController.BeginDiveResult.STARTED,
		"solution: dive starts from the solution"
	)
	_check(
		controller.has_attack_solution
			and controller.planned_release_position.is_equal_approx(
				solution.release_position
			)
			and controller.predicted_impact_position.is_equal_approx(
				solution.predicted_impact_position
			),
		"solution: positions survive begin_dive's internal reset"
	)
	_check(
		controller.get_reference_aircraft() == expected_reference,
		"reference: the controller adopts the central aircraft"
	)
	var angle_rad := deg_to_rad(clampf(dive_data.dive_angle_degrees, 1.0, 89.0))
	var expected_direction := (
		Vector3(0, 0, 1) * cos(angle_rad) + Vector3.DOWN * sin(angle_rad)
	).normalized()
	_check(
		controller.locked_dive_direction.is_equal_approx(expected_direction),
		"solution: locked dive direction matches the fixed angle contract"
	)

	# --- Whole-solution updates stop once locked.
	controller.lock_solution()
	var moved := solution.duplicate_solution()
	moved.predicted_impact_position += Vector3(500, 0, 0)
	moved.release_position += Vector3(500, 0, 0)
	controller.update_attack_solution(moved)
	_check(
		controller.predicted_impact_position.is_equal_approx(
			solution.predicted_impact_position
		),
		"lock: a locked dive ignores whole-solution updates"
	)

	# --- Second pass before any ammunition is spent: cancel, then restart
	# with a different solution. The snapshot must survive begin_dive's
	# internal reset (the historical set-then-reset wipe bug).
	controller.cancel()
	controller.reset()
	_check(
		not controller.has_attack_solution,
		"second pass: reset clears the previous solution"
	)
	var second := DiveBombAttackResolver.solve_from_dive_entry(
		squadron.formation_center,
		Vector3(0, 0, 1),
		Vector3(400.0, 0.0, 300.0),
		Vector3.ZERO,
		0.0,
		dive_data,
		weapon_data,
		GRAVITY,
		Vector3(0, 0, 1)
	)
	_check(second.valid, "second pass: new solution solves")
	var second_begin: int = controller.begin_dive_with_solution(
		second,
		AircraftSquadron.DiveControlSource.PLAYER
	)
	_check(
		second_begin == DiveBombAttackController.BeginDiveResult.STARTED,
		"second pass: dive restarts"
	)
	_check(
		controller.planned_release_position.is_equal_approx(
			second.release_position
		) and controller.predicted_impact_position.is_equal_approx(
			second.predicted_impact_position
		),
		"second pass: the new solution's positions are intact after reset"
	)

	# --- Reference stays fixed while alive, replaced only on loss.
	_check(
		controller.get_reference_aircraft() == expected_reference,
		"reference: stable while the aircraft survives"
	)
	expected_reference.health.apply_damage(99999.0)
	var replacement := controller.get_reference_aircraft()
	_check(
		replacement != null and replacement != expected_reference,
		"reference: a killed reference is replaced by a new central aircraft"
	)
	_check(
		controller.has_attack_solution,
		"reference: replacement keeps the existing solution"
	)

	# --- Release window judged from the reference aircraft.
	controller.dive_elapsed_seconds = 1.0
	var release_position: Vector3 = controller.planned_release_position
	replacement.global_position = release_position
	replacement.velocity = controller.locked_dive_direction \
		* dive_data.dive_speed_mps
	var window: int = controller._evaluate_reference_release_window(
		replacement
	)
	_check(
		window == DiveBombAttackController.ReleaseBlockReason.NONE,
		"window: aligned reference at the release point may drop (got %d)"
			% window
	)
	replacement.global_position = release_position \
		+ Vector3(dive_data.release_position_tolerance_m + 40.0, 0.0, 0.0)
	_check(
		controller._evaluate_reference_release_window(replacement)
			== DiveBombAttackController.ReleaseBlockReason \
				.RELEASE_POSITION_MISSED,
		"window: a displaced reference blocks the drop"
	)
	replacement.global_position = release_position
	replacement.velocity = -controller.locked_dive_direction \
		* dive_data.dive_speed_mps
	_check(
		controller._evaluate_reference_release_window(replacement)
			== DiveBombAttackController.ReleaseBlockReason \
				.HEADING_NOT_ALIGNED,
		"window: a misaligned heading blocks the drop"
	)

	# --- Window satisfied: every pending aircraft drops a real bomb at once.
	replacement.velocity = controller.locked_dive_direction \
		* dive_data.dive_speed_mps
	for unit in squadron.get_alive_aircraft():
		unit.global_position = release_position
		unit.velocity = replacement.velocity
	var alive_count := squadron.get_alive_aircraft().size()
	controller.update_dive(0.0)
	controller.update_dive(0.0)
	var requested := 0
	for unit in squadron.get_alive_aircraft():
		if controller.get_aircraft_release_state(unit) \
				== DiveBombAttackController.AircraftReleaseState.REQUESTED:
			requested += 1
	_check(
		requested == alive_count,
		"central release: all pending aircraft request at once (%d/%d)"
			% [requested, alive_count]
	)
	for _step in alive_count + 2:
		squadron.payload_release_coordinator.update(
			weapon_data.release_interval_sec + 0.05
		)
	if _projectile_release_count != alive_count:
		print("PROBE states=", controller.get_debug_snapshot().get(
			"aircraft_release_states", {}
		))
		print("PROBE reason=", controller.get_debug_snapshot().get(
			"release_failure_reason", ""
		))
	_check(
		_projectile_release_count == alive_count,
		"central release: every aircraft spawns a real projectile (%d/%d)"
			% [_projectile_release_count, alive_count]
	)

	await _finish(battle)


func _on_weapon_released(_aircraft: AircraftUnit, _projectile: Node) -> void:
	_projectile_release_count += 1


func _finish(battle: BattleScene) -> void:
	battle.shutdown()
	battle.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
