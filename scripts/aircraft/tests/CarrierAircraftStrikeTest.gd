extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const CARRIER_AI_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_ai_test.tres"
)
const BOMBER_DATA: AircraftData = preload(
	"res://resources/aircraft/types/basic_dive_bomber.tres"
)
const BOMB_WEAPON: AircraftWeaponData = preload(
	"res://resources/aircraft/weapons/basic_bomb_loadout.tres"
)
const BOMB_PROJECTILE: ShellProjectileData = preload(
	"res://resources/projectiles/aircraft_he_bomb.tres"
)
const STRIKE_MISSION: AirMissionData = preload(
	"res://resources/aircraft/missions/basic_dive_bombing.tres"
)
const AIRCRAFT_SCENE := preload(
	"res://scenes/aircraft/aircraft_unit.tscn"
)

var _failures: Array[String] = []
var _released_count := 0
var _mission_started_count := 0
var _mission_completed_count := 0
var _mission_failed_count := 0
var _water_impact_count := 0
var _last_projectile_data: ProjectileData
var _last_projectile_ref: WeakRef


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var event_bus := root.get_node_or_null("EventBus")
	_connect_events(event_bus)
	_check(
		BOMB_WEAPON != null and BOMB_WEAPON.is_valid_configuration(),
		"AircraftWeaponData resource loads with a valid bomb configuration"
	)
	_check(
		BOMBER_DATA.weapon_data == BOMB_WEAPON,
		"bomber AircraftData references AircraftWeaponData"
	)
	_check(
		BOMB_PROJECTILE != null \
			and BOMB_PROJECTILE.shell_type == ShellStats.ShellType.HE,
		"bomb payload reuses HE ShellProjectileData"
	)

	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = CARRIER_AI_STAGE
	root.add_child(battle)
	var carrier := _find_ship(battle, "cv_seabastion")
	var enemy := _find_hostile_ship(battle, carrier)
	var friendly := _find_friendly_ship(battle, carrier)
	_check(carrier != null and enemy != null, "battle provides carrier and target")
	if carrier == null or enemy == null:
		await _finish(battle, event_bus)
		return
	carrier.carrier_air_group_ai.shutdown()
	carrier.carrier_air_group_ai.process_mode = \
		Node.PROCESS_MODE_DISABLED
	await process_frame
	await physics_frame
	for ship_value in battle.get_battle_units():
		var ship := ship_value as ShipUnit
		if ship != null:
			ship.set_physics_process(false)
			ship.velocity = Vector3.ZERO
	enemy.health.max_health = 2000.0
	enemy.health.current_health = 2000.0

	var non_carrier := friendly
	_check(
		non_carrier != null \
			and non_carrier.carrier_air_group != null \
			and not non_carrier.carrier_air_group.can_launch_strike(),
		"non-carrier cannot launch a strike"
	)
	var fast_group := _make_fast_air_group(
		carrier.ship_data.carrier_air_group_data
	)
	carrier.carrier_air_group.setup(carrier, fast_group)
	carrier.carrier_air_group.process_mode = Node.PROCESS_MODE_INHERIT
	_check(
		carrier.carrier_air_group.launch_strike_squadron(
			"",
			friendly,
			STRIKE_MISSION
		) == null,
		"friendly target is rejected"
	)

	await _test_direct_bomb_hit(battle, carrier, enemy)
	await _test_direct_water_impact(battle, carrier)
	await _test_strike_lifecycle(battle, carrier, enemy)
	await _test_target_loss_and_carrier_loss(battle, carrier)
	await _finish(battle, event_bus)


func _test_direct_bomb_hit(
		battle: BattleScene,
		carrier: ShipUnit,
		target: ShipUnit
) -> void:
	var aircraft := _spawn_test_aircraft(battle, carrier.team)
	_check(aircraft != null, "test aircraft instantiates")
	if aircraft == null:
		return
	aircraft.global_position = target.global_position + Vector3.UP * 120.0
	aircraft.global_transform.basis = Basis.looking_at(
		Vector3.FORWARD,
		Vector3.UP
	)
	var health_before := target.health.current_health
	var ammunition_before := aircraft.weapon_controller.get_remaining_ammunition()
	var released := aircraft.weapon_controller.release(target.global_position)
	_check(released, "AircraftWeaponController releases a bomb")
	_check(
		aircraft.weapon_controller.get_remaining_ammunition() \
			== ammunition_before - 1,
		"bomb release decrements sortie ammunition"
	)
	var damaged := await _wait_until(
		func() -> bool:
			return is_instance_valid(target) \
				and target.health.current_health < health_before,
		360
	)
	_check(damaged, "bomb hit uses the existing DamageResolver path")
	_check(
		_last_projectile_data == BOMB_PROJECTILE,
		"spawned bomb receives the configured ProjectileData"
	)
	aircraft.queue_free()
	await process_frame


func _test_direct_water_impact(
		battle: BattleScene,
		carrier: ShipUnit
) -> void:
	var aircraft := _spawn_test_aircraft(battle, carrier.team)
	if aircraft == null:
		_check(false, "water-impact test aircraft instantiates")
		return
	var impact_count_before := _water_impact_count
	aircraft.global_position = Vector3(3200.0, 120.0, 3200.0)
	var released := aircraft.weapon_controller.release(
		Vector3(3200.0, 0.0, 3200.0)
	)
	_check(released, "bomb can be released over open water")
	var impacted := await _wait_until(
		func() -> bool:
			return _water_impact_count > impact_count_before,
		360
	)
	_check(impacted, "bomb water collision reuses WaterImpactService")
	await process_frame
	var pooled_projectile: Variant = _last_projectile_ref.get_ref() \
		if _last_projectile_ref != null else null
	if pooled_projectile is Projectile:
		var shell := pooled_projectile as Projectile
		_check(
			not shell.active and shell.projectile_data == null,
			"pooled bomb clears active runtime projectile state"
		)
	aircraft.queue_free()
	await process_frame


func _test_strike_lifecycle(
		battle: BattleScene,
		carrier: ShipUnit,
		target: ShipUnit
) -> void:
	_reset_event_counts()
	var attack_direction := -carrier.global_transform.basis.z
	attack_direction.y = 0.0
	attack_direction = attack_direction.normalized()
	target.global_position = carrier.global_position + attack_direction * 700.0
	target.velocity = Vector3.ZERO
	var squadron := carrier.carrier_air_group.launch_strike_squadron(
		"basic_bomber_squadron",
		target,
		STRIKE_MISSION
	)
	_check(squadron != null, "carrier launches a strike squadron")
	if squadron == null:
		return
	for aircraft in squadron.aircraft_units:
		_check(
			aircraft.weapon_controller.get_remaining_ammunition() \
				== BOMB_WEAPON.ammunition_per_sortie,
			"each aircraft starts the sortie with full ammunition"
		)
	var released := await _wait_until(
		func() -> bool:
			return _released_count >= squadron.aircraft_units.size(),
		900
	)
	_check(released, "strike releases bombs from surviving aircraft")
	_check(
		_mission_started_count == 1,
		"strike emits one mission-start event"
	)
	var recovered := await _wait_until(
		func() -> bool:
			return carrier.carrier_air_group.get_active_squadrons().is_empty(),
		1500
	)
	_check(recovered, "completed strike returns through Stage 1 recovery")
	_check(
		_mission_completed_count == 1,
		"strike emits one mission-completed event"
	)
	carrier.carrier_air_group.call(&"_process", 1.0)


func _test_target_loss_and_carrier_loss(
		battle: BattleScene,
		carrier: ShipUnit
) -> void:
	var target := _find_hostile_ship(battle, carrier)
	if target == null:
		_check(false, "secondary hostile target exists")
		return
	target.global_position = carrier.global_position + Vector3(0.0, 0.0, -650.0)
	target.velocity = Vector3.ZERO
	var squadron := carrier.carrier_air_group.launch_strike_squadron(
		"basic_bomber_squadron",
		target,
		STRIKE_MISSION
	)
	_check(squadron != null, "second strike launches after rearm")
	if squadron == null:
		return
	var failures_before := _mission_failed_count
	target.queue_free()
	await process_frame
	var returning := await _wait_until(
		func() -> bool:
			return is_instance_valid(squadron) \
				and (
					squadron.state == AircraftSquadron.State.RETURNING
					or _mission_failed_count > failures_before
				),
		120
	)
	_check(returning, "missing strike target triggers safe mission failure")
	var squadron_instance_id := squadron.get_instance_id()
	carrier.carrier_air_group.call(&"_on_owner_ship_died")
	var cleaned := await _wait_until(
		func() -> bool:
			return not is_instance_id_valid(squadron_instance_id),
		240
	)
	_check(cleaned, "carrier loss cleans active squadron after grace period")


func _spawn_test_aircraft(
		battle: BattleScene,
		team: StringName
) -> AircraftUnit:
	var aircraft := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	var aircraft_root := battle.get_node_or_null("Aircraft")
	if aircraft == null or aircraft_root == null:
		return null
	aircraft_root.add_child(aircraft)
	aircraft.setup(BOMBER_DATA, team, Vector3.ZERO)
	return aircraft


func _make_fast_air_group(
		source: CarrierAirGroupData
) -> CarrierAirGroupData:
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
	template.aircraft_data = aircraft
	return result


func _wait_until(condition: Callable, maximum_frames: int) -> bool:
	for _frame in range(maximum_frames):
		if bool(condition.call()):
			return true
		await physics_frame
	return false


func _find_ship(battle: BattleScene, ship_id: String) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null \
				and ship.ship_id == ship_id \
				and (
					ship_id != "cv_seabastion" \
					or ship.team == FactionRelations.ALLY
				):
			return ship
	return null


func _find_hostile_ship(
		battle: BattleScene,
		carrier: ShipUnit
) -> ShipUnit:
	if carrier == null:
		return null
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null and carrier.is_hostile_to(ship):
			return ship
	return null


func _find_friendly_ship(
		battle: BattleScene,
		carrier: ShipUnit
) -> ShipUnit:
	if carrier == null:
		return null
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null and ship != carrier \
				and not carrier.is_hostile_to(ship) \
				and (
					ship.ship_data == null \
					or ship.ship_data.carrier_air_group_data == null
				):
			return ship
	return null


func _connect_events(event_bus: Node) -> void:
	if event_bus == null:
		return
	event_bus.aircraft_weapon_released.connect(_on_weapon_released)
	event_bus.air_mission_started.connect(_on_mission_started)
	event_bus.air_mission_completed.connect(_on_mission_completed)
	event_bus.air_mission_failed.connect(_on_mission_failed)
	event_bus.projectile_water_impact.connect(_on_water_impact)


func _disconnect_events(event_bus: Node) -> void:
	if event_bus == null:
		return
	var connections := [
		[event_bus.aircraft_weapon_released, _on_weapon_released],
		[event_bus.air_mission_started, _on_mission_started],
		[event_bus.air_mission_completed, _on_mission_completed],
		[event_bus.air_mission_failed, _on_mission_failed],
		[event_bus.projectile_water_impact, _on_water_impact],
	]
	for entry in connections:
		var signal_value: Signal = entry[0]
		var callable_value: Callable = entry[1]
		if signal_value.is_connected(callable_value):
			signal_value.disconnect(callable_value)


func _on_weapon_released(_aircraft, projectile: Node) -> void:
	_released_count += 1
	if projectile != null and is_instance_valid(projectile):
		_last_projectile_ref = weakref(projectile)
		_last_projectile_data = projectile.get("projectile_data") \
			as ProjectileData


func _on_mission_started(_squadron, _target) -> void:
	_mission_started_count += 1


func _on_mission_completed(_squadron) -> void:
	_mission_completed_count += 1


func _on_mission_failed(_squadron) -> void:
	_mission_failed_count += 1


func _on_water_impact(_position: Vector3, _strength: float) -> void:
	_water_impact_count += 1


func _reset_event_counts() -> void:
	_released_count = 0
	_mission_started_count = 0
	_mission_completed_count = 0
	_mission_failed_count = 0


func _finish(battle: BattleScene, event_bus: Node) -> void:
	_disconnect_events(event_bus)
	if is_instance_valid(battle):
		battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER AIRCRAFT STRIKE TEST: %s" % failure)
	print(
		"CARRIER_AIRCRAFT_STRIKE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
