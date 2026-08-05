extends SceneTree
## End-to-end projectile check for designation-based player dive bombing:
##   1. an ocean designation near a MOVING hostile ship auto-acquires it and
##      the reference bomb lands on the ship (target velocity reflected)
##   2. a designation with no ship in the radius drops on the designated
##      point itself
## Both scenarios fly the full player run and spawn real bomb projectiles.

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const SHIP_TOLERANCE_M := 40.0
const POSITION_TOLERANCE_M := 30.0
const MAX_FRAMES := 3600

var _failures: Array[String] = []
var _released_projectiles: Array[WeakRef] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _run_ship_acquire_scenario()
	await _run_position_fallback_scenario()
	print(
		"DIVE_BOMB_DESIGNATION_IMPACT_TEST failures=%d" % _failures.size()
	)
	for failure in _failures:
		push_error("DESIGNATION IMPACT: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _run_ship_acquire_scenario() -> void:
	_released_projectiles.clear()
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await physics_frame
	var carrier := battle.player_ship as ShipUnit
	var target := _find_enemy(battle)
	_check(carrier != null and target != null, "acquire: ships exist")
	if carrier == null or target == null:
		await _finish(battle)
		return
	var target_velocity := Vector3(10.0, 0.0, 0.0)
	target.set_physics_process(false)
	target.velocity = target_velocity
	target.global_position = carrier.global_position \
		+ Vector3(0.0, 0.0, 2200.0)
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null, "acquire: squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	for aircraft in squadron.aircraft_units:
		aircraft.weapon_controller.weapon_released.connect(
			_on_weapon_released
		)
	# Ocean click 120 m from the moving ship: inside the acquisition radius.
	var designation := target.global_position + Vector3(120.0, 0.0, 0.0)
	designation.y = 0.0
	_check(
		squadron.issue_player_move_command(Vector3.ZERO, null),
		"acquire: player takes command"
	)
	_check(
		squadron.begin_manual_dive_at(designation, 30.0, null),
		"acquire: designation order starts the run"
	)
	var run := squadron._player_dive_run
	_check(
		run != null and run.get_resolved_target().get_ship() == target,
		"acquire: the moving ship is auto-acquired"
	)
	var controller := squadron.dive_bomb_controller
	var measured := await _fly_until_reference_impact(
		squadron,
		controller,
		target,
		target_velocity
	)
	if measured.is_empty():
		_check(false, "acquire: the reference bomb impacts in budget")
	else:
		var impact: Vector3 = measured["impact"]
		var ship_at_impact: Vector3 = measured["target"]
		var error := impact - ship_at_impact
		error.y = 0.0
		print(
			"MEASURE acquire impact_error_m=%.1f impact=%s ship=%s"
			% [error.length(), impact, ship_at_impact]
		)
		_check(
			error.length() <= SHIP_TOLERANCE_M,
			"acquire: bomb lands within %.0f m of the moving ship (%.1f m)"
				% [SHIP_TOLERANCE_M, error.length()]
		)
	await _finish(battle)


func _run_position_fallback_scenario() -> void:
	_released_projectiles.clear()
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await physics_frame
	var carrier := battle.player_ship as ShipUnit
	var target := _find_enemy(battle)
	_check(carrier != null and target != null, "fallback: ships exist")
	if carrier == null or target == null:
		await _finish(battle)
		return
	# Push every hostile ship far outside the radius.
	target.set_physics_process(false)
	target.velocity = Vector3.ZERO
	target.global_position = carrier.global_position \
		+ Vector3(9000.0, 0.0, 0.0)
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null, "fallback: squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	for aircraft in squadron.aircraft_units:
		aircraft.weapon_controller.weapon_released.connect(
			_on_weapon_released
		)
	var designation := carrier.global_position + Vector3(0.0, 0.0, 2200.0)
	designation.y = 0.0
	_check(
		squadron.issue_player_move_command(Vector3.ZERO, null),
		"fallback: player takes command"
	)
	_check(
		squadron.begin_manual_dive_at(designation, 30.0, null),
		"fallback: designation order starts the run"
	)
	var run := squadron._player_dive_run
	_check(
		run != null and run.get_resolved_target().is_position_target(),
		"fallback: the empty designation stays a position target"
	)
	var controller := squadron.dive_bomb_controller
	var measured := await _fly_until_reference_impact(
		squadron,
		controller,
		null,
		Vector3.ZERO
	)
	if measured.is_empty():
		_check(false, "fallback: the reference bomb impacts in budget")
	else:
		var impact: Vector3 = measured["impact"]
		var error := impact - designation
		error.y = 0.0
		print(
			"MEASURE fallback impact_error_m=%.1f impact=%s point=%s"
			% [error.length(), impact, designation]
		)
		_check(
			error.length() <= POSITION_TOLERANCE_M,
			"fallback: bomb lands within %.0f m of the point (%.1f m)"
				% [POSITION_TOLERANCE_M, error.length()]
		)
	await _finish(battle)


## Runs the battle until the reference aircraft's bomb despawns; returns the
## impact position (and the target ship position at that moment, when a
## target is tracked).
func _fly_until_reference_impact(
		squadron: AircraftSquadron,
		controller: DiveBombAttackController,
		target: ShipUnit,
		target_velocity: Vector3
) -> Dictionary:
	var physics_delta := 1.0 / float(Engine.physics_ticks_per_second)
	var reference_id := 0
	var reference_projectile: Projectile = null
	var solution_seen := false
	for _frame in MAX_FRAMES:
		if target != null and is_instance_valid(target):
			target.global_position += target_velocity * physics_delta
		await physics_frame
		if not is_instance_valid(squadron):
			break
		if controller.has_attack_solution:
			solution_seen = true
		if reference_id == 0 and controller.has_attack_solution:
			reference_id = controller.get_reference_aircraft_instance_id()
		if reference_projectile == null and reference_id != 0:
			reference_projectile = _find_reference_projectile(reference_id)
		if reference_projectile != null \
				and is_instance_valid(reference_projectile) \
				and not reference_projectile.active:
			_check(
				solution_seen,
				"the player run flies a central attack solution"
			)
			return {
				"impact": reference_projectile.last_despawn_position,
				"target": target.global_position \
					if target != null and is_instance_valid(target) \
					else Vector3.ZERO,
			}
	return {}


func _find_reference_projectile(reference_id: int) -> Projectile:
	for reference in _released_projectiles:
		var value: Variant = reference.get_ref()
		if value == null or not is_instance_valid(value):
			continue
		var projectile := value as Projectile
		if projectile == null:
			continue
		if projectile.get_meta(
			"dive_bomb_source_aircraft_id", 0
		) == reference_id:
			return projectile
	return null


func _on_weapon_released(
		aircraft: AircraftUnit,
		projectile: Node
) -> void:
	if projectile == null:
		return
	projectile.set_meta(
		"dive_bomb_source_aircraft_id",
		aircraft.get_instance_id()
	)
	_released_projectiles.append(weakref(projectile))


func _find_enemy(battle: BattleScene) -> ShipUnit:
	for ship_value in battle.enemies:
		var ship := ship_value as ShipUnit
		if ship != null and is_instance_valid(ship):
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	battle.shutdown()
	battle.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
