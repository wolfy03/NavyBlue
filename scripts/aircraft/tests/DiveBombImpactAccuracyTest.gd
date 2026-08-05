extends SceneTree
## Real-projectile regression for the shared per-aircraft dive-bomb path.

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const STRIKE_MISSION: AirMissionData = preload(
	"res://resources/aircraft/missions/basic_dive_bombing.tres"
)
const STATIC_TOLERANCE_M := 35.0
const MOVING_TOLERANCE_M := 30.0
const CROSSING_TOLERANCE_M := 35.0
const MAX_FRAMES := 3600

var _failures: Array[String] = []
var _released_projectiles: Array[WeakRef] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _run_scenario(
		"default_profile",
		Vector3.ZERO,
		60.0,
		700.0,
		false
	)
	await _run_scenario("static", Vector3.ZERO, STATIC_TOLERANCE_M)
	await _run_scenario(
		"moving", Vector3(0.0, 0.0, 12.0), MOVING_TOLERANCE_M
	)
	await _run_scenario(
		"crossing", Vector3(12.0, 0.0, 0.0), CROSSING_TOLERANCE_M
	)
	print("DIVE_BOMB_IMPACT_ACCURACY_TEST failures=%d" % _failures.size())
	for failure in _failures:
		push_error("DIVE BOMB IMPACT ACCURACY: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _run_scenario(
		label: String,
		target_velocity: Vector3,
		tolerance_m: float,
		target_distance_m: float = 2200.0,
		use_fast_fixture: bool = true
) -> void:
	_released_projectiles.clear()
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await physics_frame
	var carrier := battle.player_ship as ShipUnit
	var target := _find_enemy(battle)
	_check(carrier != null and target != null, label + ": scenario ships exist")
	if carrier == null or target == null:
		await _finish_battle(battle)
		return
	if carrier.carrier_air_group_ai != null:
		carrier.carrier_air_group_ai.shutdown()
		carrier.carrier_air_group_ai.process_mode = Node.PROCESS_MODE_DISABLED
	for ship_value in battle.get_battle_units():
		var ship := ship_value as ShipUnit
		if ship != null:
			ship.set_physics_process(false)
			ship.velocity = Vector3.ZERO
	if use_fast_fixture:
		carrier.carrier_air_group.setup(
			carrier,
			_make_fast_air_group(carrier.ship_data.carrier_air_group_data)
		)
	carrier.carrier_air_group.process_mode = Node.PROCESS_MODE_INHERIT
	target.set_physics_process(false)
	target.velocity = target_velocity
	target.global_position = carrier.global_position \
		+ Vector3(0.0, 0.0, target_distance_m)
	var target_health_before := target.health.current_health
	var squadron := carrier.carrier_air_group.launch_strike_squadron(
		"basic_bomber_squadron",
		target,
		STRIKE_MISSION
	)
	_check(squadron != null, label + ": strike squadron launches")
	if squadron == null:
		await _finish_battle(battle)
		return
	for aircraft in squadron.aircraft_units:
		aircraft.weapon_controller.weapon_released.connect(_on_weapon_released)
	var observed_projectile: Projectile
	var impact_position := Vector3.INF
	var target_at_impact := Vector3.INF
	var physics_delta := 1.0 / float(Engine.physics_ticks_per_second)
	var last_debug := {}
	var last_squadron_state := "missing"
	var last_ammunition := -1
	for _frame in MAX_FRAMES:
		if is_instance_valid(target):
			target.global_position += target_velocity * physics_delta
		await physics_frame
		if is_instance_valid(squadron):
			last_squadron_state = AircraftSquadron.State.keys()[int(
				squadron.state
			)]
			last_ammunition = squadron.get_total_remaining_ammunition()
			var active_behavior := squadron.mission_controller \
				.dive_bomb_behavior as DiveBombMissionBehavior
			if active_behavior != null:
				last_debug = active_behavior.get_debug_snapshot()
		if observed_projectile == null:
			observed_projectile = _get_first_projectile()
		if observed_projectile != null \
				and is_instance_valid(observed_projectile) \
				and not observed_projectile.active:
			impact_position = observed_projectile.last_despawn_position
			target_at_impact = target.global_position \
				if is_instance_valid(target) else Vector3.INF
			break
	if not impact_position.is_finite():
		print(
			"TIMEOUT %s state=%s ammo=%d debug=%s"
			% [
				label,
				last_squadron_state,
				last_ammunition,
				last_debug,
			]
		)
	_check(
		impact_position.is_finite() and target_at_impact.is_finite(),
		label + ": an independently released bomb impacts within the frame budget"
	)
	if impact_position.is_finite() and target_at_impact.is_finite():
		await process_frame
		var error := impact_position - target_at_impact
		error.y = 0.0
		print("MEASURE %s impact_error_m=%.1f" % [label, error.length()])
		_check(
			error.length() <= tolerance_m,
			"%s: bomb lands within %.0f m of target (got %.1f m)"
				% [label, tolerance_m, error.length()]
		)
		_check(
			is_instance_valid(target) \
				and target.health.current_health < target_health_before,
			label + ": real projectile damage confirms a hull hit"
		)
	if not use_fast_fixture:
		var return_started := false
		for _frame in MAX_FRAMES:
			if not is_instance_valid(squadron):
				return_started = true
				break
			if squadron.state in [
				AircraftSquadron.State.RETURNING,
				AircraftSquadron.State.RECOVERING,
			]:
				return_started = true
				break
			await physics_frame
		_check(
			return_started,
			label + ": AI strike starts carrier return after the attack"
		)
		if not return_started and is_instance_valid(squadron):
			var behavior := squadron.mission_controller.dive_bomb_behavior \
				as DiveBombMissionBehavior
			print(
				"RETURN TIMEOUT state=%s center=%s destination=%s debug=%s"
				% [
					AircraftSquadron.State.keys()[int(squadron.state)],
					squadron.formation_center,
					squadron.destination,
					behavior.get_debug_snapshot() if behavior != null else {},
				]
			)
		if return_started and is_instance_valid(squadron) \
				and squadron.state == AircraftSquadron.State.RETURNING:
			# Reproduce the problematic post-strike geometry: the carrier is
			# tangent to the formation's current heading and closer than the
			# bomber's full-speed turn diameter. Pure pursuit circles forever.
			var recovery_position := squadron \
				._get_carrier_recovery_position()
			squadron.formation_center = recovery_position \
				+ Vector3(150.0, 0.0, 0.0)
			squadron.formation_center.y = recovery_position.y
			squadron._formation_forward = Vector3.FORWARD
			for aircraft in squadron.get_alive_aircraft():
				aircraft.global_position = squadron.formation_center \
					+ aircraft.formation_offset
			var recovery_completed := false
			for _frame in 900:
				if not is_instance_valid(squadron) \
						or squadron.state \
							== AircraftSquadron.State.RECOVERING:
					recovery_completed = true
					break
				await physics_frame
			_check(
				recovery_completed,
				label + ": return steering reaches carrier from a tangential approach"
			)
	await _finish_battle(battle)


func _get_first_projectile() -> Projectile:
	for reference in _released_projectiles:
		var value: Variant = reference.get_ref()
		if value != null and is_instance_valid(value) and value is Projectile:
			return value as Projectile
	return null


func _on_weapon_released(_aircraft: AircraftUnit, projectile: Node) -> void:
	if projectile != null:
		_released_projectiles.append(weakref(projectile))


func _find_enemy(battle: BattleScene) -> ShipUnit:
	for ship_value in battle.enemies:
		if ship_value != null and is_instance_valid(ship_value) \
				and ship_value is ShipUnit:
			return ship_value as ShipUnit
	return null


func _make_fast_air_group(source: CarrierAirGroupData) -> CarrierAirGroupData:
	var result := source.duplicate(true) as CarrierAirGroupData
	result.launch_cooldown_sec = 0.05
	result.recovery_cooldown_sec = 0.05
	var template := result.squadron_templates[0]
	template.rearm_duration_sec = 0.05
	template.launch_interval_sec = 0.01
	var aircraft := template.aircraft_data.duplicate(true) as AircraftData
	aircraft.cruise_speed_mps = 120.0
	aircraft.maximum_speed_mps = 120.0
	aircraft.turn_rate_deg_sec = 180.0
	aircraft.operating_altitude_m = 80.0
	aircraft.arrival_distance_m = 24.0
	var dive_data := aircraft.dive_bomber_combat_data.duplicate(
		true
	) as DiveBomberCombatData
	dive_data.dive_entry_altitude_m = 150.0
	dive_data.approach_distance_m = 300.0
	dive_data.dive_entry_horizontal_distance_m = 100.0
	dive_data.dive_speed_mps = 240.0
	dive_data.minimum_dive_time_before_release_sec = 0.1
	dive_data.minimum_release_altitude_m = 50.0
	dive_data.maximum_release_altitude_m = 130.0
	dive_data.automatic_pull_out_altitude_m = 30.0
	aircraft.dive_bomber_combat_data = dive_data
	template.aircraft_data = aircraft
	return result


func _finish_battle(battle: BattleScene) -> void:
	battle.shutdown()
	battle.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
