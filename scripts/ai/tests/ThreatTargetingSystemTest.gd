extends SceneTree

class FakeDeviatedNavigation:
	extends RefCounted

	var has_navigation_target := true
	var path_calculation_failed_state := false
	var update_count := 0
	var last_target := Vector3.ZERO

	func has_valid_path() -> bool:
		return true

	func is_path_deviated(_threshold_m: float = -1.0) -> bool:
		return true

	func set_navigation_target(target: Vector3) -> void:
		last_target = target
		update_count += 1


var _failures: Array[String] = []
var _check_count := 0
var _arena: Node3D
var _provider_units: Array = []
var _shared_tracker := FleetTargetAssignmentTracker.new()
var _ship_scene := preload("res://scenes/unit/ship.tscn")
var _ship_database := ShipDatabase.new()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _test_navigation_recalculation_policy()
	await _test_emergency_pursuit_cooldown()
	await _test_si_upgrades_and_run_serialization()
	await _test_focus_fire_distribution_and_role_scores()
	await _test_target_lock_and_emergency_switch()
	await _test_damage_source_and_threat_decay()
	await _test_projectile_source_reset()
	await _test_debug_and_long_duration_simulation()
	print(
		"THREAT_TARGETING checks=%d failures=%d" % [
			_check_count,
			_failures.size(),
		]
	)
	for failure in _failures:
		push_error("THREAT TARGETING TEST: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _test_navigation_recalculation_policy() -> void:
	_begin_arena()
	var ship := _spawn_ship("dd_bluewind", &"player", Vector3.ZERO, true)
	ship.set_physics_process(false)
	ship.navigation.set_navigation_target(Vector3(5000.0, 0.0, 0.0))
	var initial_count := ship.navigation.path_calculation_count
	for _step in 180:
		ship.navigation.update_navigation(1.0 / 60.0)
	_check(
		ship.navigation.path_calculation_count == initial_count,
		"a valid fixed route is not recalculated periodically"
	)
	ship.navigation.request_path_recalculation()
	ship.navigation.update_navigation(1.0 / 60.0)
	_check(
		ship.navigation.path_calculation_count == initial_count + 1,
		"an explicit path recalculation request is honored"
	)
	_end_arena()


func _test_emergency_pursuit_cooldown() -> void:
	_begin_arena()
	var hunter := _spawn_ship("dd_bluewind", &"ally", Vector3.ZERO)
	var target := _spawn_ship("dd_bluewind", &"enemy", Vector3(16000.0, 0.0, 0.0))
	hunter.set_physics_process(false)
	target.set_physics_process(false)
	hunter.ai.set_target(target)
	var fake_navigation := FakeDeviatedNavigation.new()
	hunter.ai.pursuit_update_elapsed_sec = 0.0
	for _step in 60:
		hunter.ai.pursuit_update_elapsed_sec += 1.0 / 60.0
		hunter.ai.call(&"_update_pursuit", hunter, target, fake_navigation)
	_check(
		fake_navigation.update_count >= 3 and fake_navigation.update_count <= 4,
		"persistent 500 m path deviation is throttled to the 0.3 s emergency cooldown"
	)
	_check(
		fake_navigation.update_count < 10,
		"emergency pursuit does not submit a navigation target every physics frame"
	)
	_end_arena()


func _test_si_upgrades_and_run_serialization() -> void:
	_begin_arena()
	var ship := _spawn_ship("dd_bluewind", &"player", Vector3.ZERO, true)
	ship.set_physics_process(false)
	var base_speed := ship.ship_data.max_speed_mps
	var base_acceleration := ship.ship_data.acceleration_mps2
	var base_turn_rate := ship.ship_data.max_turn_rate_deg_sec
	var upgrades: Array = [
		load("res://resources/upgrades/engine_tuning_1.tres"),
		load("res://resources/upgrades/acceleration_tuning_1.tres"),
		load("res://resources/upgrades/steering_gear_1.tres"),
	]
	var upgrade_system := UpgradeSystem.new()
	upgrade_system.apply_upgrades_to_ship(ship, upgrades)
	_check(
		is_equal_approx(ship.ship_data.max_speed_mps, base_speed * 1.08),
		"maximum-speed upgrade modifies max_speed_mps"
	)
	_check(
		is_equal_approx(ship.ship_data.acceleration_mps2, base_acceleration * 1.10),
		"acceleration upgrade modifies acceleration_mps2"
	)
	_check(
		is_equal_approx(ship.ship_data.max_turn_rate_deg_sec, base_turn_rate * 1.10),
		"steering upgrade modifies max_turn_rate_deg_sec"
	)
	_check(
		ship.movement.ship_data == ship.ship_data,
		"ShipMovement receives the upgraded SI runtime resource"
	)
	ship.movement.set_movement_command(1.0, 0.0)
	for _step in 1000:
		ship.movement.apply_movement(0.1)
	_check(
		is_equal_approx(ship.movement.current_speed_mps, ship.ship_data.max_speed_mps),
		"the movement controller reaches the upgraded SI maximum speed"
	)

	var run_manager: Node = root.get_node("RunManager")
	var original_run_data: Dictionary = run_manager.call(&"to_save_data")
	run_manager.call(&"start_new_run", {"upgrades": [
		"engine_tuning_1",
		"acceleration_tuning_1",
		"steering_gear_1",
	]})
	var saved_data: Dictionary = run_manager.call(&"to_save_data")
	run_manager.call(&"reset_run")
	run_manager.call(&"restore_from_save_data", saved_data)
	var restored_upgrades: Array = run_manager.get(&"active_upgrades")
	_check(
		restored_upgrades.size() == 3
			and str(restored_upgrades[0]) == "engine_tuning_1"
			and str(restored_upgrades[1]) == "acceleration_tuning_1"
			and str(restored_upgrades[2]) == "steering_gear_1",
		"SI upgrade IDs survive the run save/restore data flow"
	)
	run_manager.call(&"restore_from_save_data", original_run_data)
	upgrade_system.free()
	_end_arena()


func _test_focus_fire_distribution_and_role_scores() -> void:
	_begin_arena()
	_shared_tracker.clear_all()
	var allies: Array[ShipUnit] = []
	var enemies: Array[ShipUnit] = []
	for index in 3:
		var ally := _spawn_ship(
			"dd_bluewind",
			&"ally",
			Vector3(-6500.0, 0.0, float(index) * 20.0)
		)
		ally.set_physics_process(false)
		allies.append(ally)
	for index in 3:
		var enemy := _spawn_ship(
			"dd_bluewind",
			&"enemy",
			Vector3(0.0, 0.0, 0.0)
		)
		enemy.set_physics_process(false)
		enemies.append(enemy)
	_provider_units.assign(allies)
	_provider_units.append_array(enemies)
	for ship in allies:
		ship.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
		ship.targeting.request_immediate_evaluation()
		ship.targeting.update_targeting(0.0)
	var assigned_target_ids: Dictionary = {}
	for ship in allies:
		var selected := ship.get_ai_target() as ShipUnit
		if selected != null:
			assigned_target_ids[selected.get_instance_id()] = true
	_check(
		assigned_target_ids.size() == 3,
		"three equal AI attackers distribute across three equal targets"
	)
	_check(
		_shared_tracker.get_attacker_count(enemies[0]) == 1
			and _shared_tracker.get_attacker_count(enemies[1]) == 1
			and _shared_tracker.get_attacker_count(enemies[2]) == 1,
		"target assignment counts remain consistent"
	)

	var destroyer_owner := allies[0]
	var cruiser_target := _spawn_ship("cl_tidebreaker", &"enemy", Vector3.ZERO)
	var battleship_target := _spawn_ship("bb_ironwake", &"enemy", Vector3.ZERO)
	var carrier_target := _spawn_ship("cv_seabastion", &"enemy", Vector3.ZERO)
	for target in [cruiser_target, battleship_target, carrier_target]:
		target.set_physics_process(false)
	var cruiser_class_score := float(
		destroyer_owner.targeting.get_debug_score_breakdown(cruiser_target).get(
			"target_class_score",
			0.0
		)
	)
	var battleship_class_score := float(
		destroyer_owner.targeting.get_debug_score_breakdown(battleship_target).get(
			"target_class_score",
			0.0
		)
	)
	var carrier_class_score := float(
		destroyer_owner.targeting.get_debug_score_breakdown(carrier_target).get(
			"target_class_score",
			0.0
		)
	)
	_check(
		carrier_class_score > battleship_class_score
			and battleship_class_score > cruiser_class_score,
		"destroyer role class preferences favor carriers and capital ships"
	)
	_end_arena()


func _test_target_lock_and_emergency_switch() -> void:
	_begin_arena()
	_shared_tracker.clear_all()
	var owner := _spawn_ship("dd_bluewind", &"ally", Vector3.ZERO)
	var locked_target := _spawn_ship("dd_bluewind", &"enemy", Vector3(15000.0, 0.0, 0.0))
	var challenger := _spawn_ship("dd_bluewind", &"enemy", Vector3(6800.0, 0.0, 0.0))
	for ship in [owner, locked_target, challenger]:
		ship.set_physics_process(false)
	_provider_units = [owner, locked_target, challenger]
	owner.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	owner.set_ai_target(locked_target)
	owner.targeting.request_immediate_evaluation()
	owner.targeting.update_targeting(0.0)
	_check(
		owner.get_ai_target() == locked_target
			and owner.targeting.best_candidate == challenger,
		"minimum target lock retains a valid target despite a better normal candidate"
	)
	owner.targeting.current_target_lock_sec = owner.ship_data.ai_role_profile.minimum_target_lock_sec + 0.1
	owner.targeting.request_immediate_evaluation()
	owner.targeting.update_targeting(0.0)
	_check(
		owner.get_ai_target() == challenger,
		"target switches after lock expiry when the score threshold is exceeded"
	)

	owner.set_ai_target(locked_target)
	owner.targeting.register_damage_source(
		challenger,
		100.0,
		{"weapon_id": &"test_weapon", "projectile_type": &"ap"}
	)
	owner.targeting.update_targeting(0.0)
	_check(
		owner.get_ai_target() == challenger,
		"an emergency recent-damage threat can override the target lock"
	)
	_check(
		owner.ai.target == owner.combat.target and owner.ai.target == owner.get_ai_target(),
		"ShipAI and ShipCombat receive the component-owned target atomically"
	)
	_end_arena()


func _test_damage_source_and_threat_decay() -> void:
	_begin_arena()
	var victim := _spawn_ship("cl_tidebreaker", &"ally", Vector3.ZERO)
	var attacker := _spawn_ship("dd_bluewind", &"enemy", Vector3(4000.0, 0.0, 0.0))
	victim.set_physics_process(false)
	attacker.set_physics_process(false)
	victim.health.debug_damage_log = false
	_provider_units = [victim, attacker]
	victim.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	var hit_info := HitInfo.new()
	hit_info.set_damage_source(attacker, attacker.get_instance_id(), &"destroyer_cannon")
	hit_info.projectile_info = {"projectile_type": "ap"}
	victim.health.apply_damage(50.0, PenetrationResolver.Result.PENETRATED, hit_info)
	var snapshot := victim.targeting.get_threat_memory().get_snapshot(attacker)
	_check(
		float(snapshot["damage_to_owner"]) > 0.0
			and snapshot["weapon_id"] == &"destroyer_cannon"
			and int(snapshot["source_ship_instance_id"]) == attacker.get_instance_id(),
		"ShipHealth forwards projectile attacker and weapon data to threat memory"
	)
	victim.targeting.update_targeting(0.0)
	var breakdown := victim.targeting.get_debug_score_breakdown(attacker)
	_check(
		float(breakdown.get("recent_damage_score", 0.0)) > 0.0,
		"recent attacker damage raises the target score"
	)

	var memory := ThreatMemory.new()
	var memory_attacker := Node.new()
	memory.register_damage(memory_attacker, 80.0, true, {}, 100.0)
	var initial := memory.get_snapshot(memory_attacker, 100.0)
	var half_life := memory.get_snapshot(memory_attacker, 112.0)
	_check(
		is_equal_approx(float(initial["damage_to_owner"]), 80.0)
			and is_equal_approx(float(half_life["damage_to_owner"]), 40.0),
		"threat memory decays exponentially with a 12 second half-life"
	)
	memory_attacker.free()
	memory.cleanup(200.0)
	_check(memory.get_entry_count() == 0, "invalid weak threat-memory entries are cleaned")
	_end_arena()


func _test_projectile_source_reset() -> void:
	var attacker := Node.new()
	var projectile := Projectile.new()
	root.add_child(projectile)
	projectile.launch(
		Vector3(0.0, 10.0, 100.0),
		&"ally",
		null,
		attacker,
		&"test_weapon"
	)
	_check(
		projectile.source_ship_instance_id == attacker.get_instance_id()
			and projectile.source_weapon_id == &"test_weapon",
		"projectile launch records its source ship and weapon"
	)
	projectile.on_recycled_to_pool()
	_check(
		projectile.source_ship_instance_id == 0
			and projectile.source_weapon_id.is_empty(),
		"pooled projectile clears stale attacker identity"
	)
	projectile.queue_free()
	await process_frame
	attacker.free()


func _test_debug_and_long_duration_simulation() -> void:
	_begin_arena()
	_shared_tracker.clear_all()
	var owner := _spawn_ship("cl_tidebreaker", &"ally", Vector3.ZERO)
	var enemy := _spawn_ship("dd_bluewind", &"enemy", Vector3(9000.0, 0.0, 0.0))
	owner.set_physics_process(false)
	enemy.set_physics_process(false)
	_provider_units = [owner, enemy]
	owner.configure_ai_target_provider(Callable(self, &"_get_provider_units"))
	owner.set_ai_debug_enabled(true)
	owner.targeting.request_immediate_evaluation()
	owner.targeting.update_targeting(0.0)
	var initial_target := owner.get_ai_target() as ShipUnit
	for _step in 6000:
		owner.targeting.update_targeting(0.1)
	var debug_data := owner.get_ai_debug_data()
	_check(
		owner.get_ai_target() == initial_target,
		"a stable candidate remains locked without rapid switching over a simulated 10 minutes"
	)
	_check(
		owner.targeting.target_evaluation_count >= 400
			and owner.targeting.target_evaluation_count <= 700,
		"target evaluation remains approximately once per second in a 10-minute simulation"
	)
	_check(
		debug_data.has("current_target_score")
			and debug_data.has("current_breakdown")
			and debug_data.has("pursuit_navigation_update_count")
			and debug_data.has("navigation_path_calculation_count"),
		"opt-in AI debug data exposes targeting, pursuit, and path counters"
	)
	_end_arena()


func _begin_arena() -> void:
	_arena = Node3D.new()
	root.add_child(_arena)
	_provider_units.clear()
	_shared_tracker = FleetTargetAssignmentTracker.new()


func _end_arena() -> void:
	_shared_tracker.clear_all()
	_provider_units.clear()
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	await process_frame
	await physics_frame
	_arena = null


func _spawn_ship(
		ship_id: String,
		team: StringName,
		position: Vector3,
		is_player := false
) -> ShipUnit:
	var ship := _ship_scene.instantiate() as ShipUnit
	var source_data := _ship_database.get_ship(ship_id)
	ship.setup(source_data.duplicate(true) as ShipData, team, is_player, Color.WHITE)
	_arena.add_child(ship)
	ship.global_position = position
	ship.targeting.set_assignment_tracker(_shared_tracker)
	return ship


func _get_provider_units() -> Array:
	var valid_units: Array = []
	for ship in _provider_units:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			valid_units.append(ship)
	return valid_units


func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(description)
