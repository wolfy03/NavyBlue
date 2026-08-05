extends SceneTree
## Measures where the reference dive bomb ACTUALLY lands versus where the
## target ship actually is at that moment, for a static, a chasing and a
## crossing constant-velocity target. This is both the diagnostic instrument
## for the "bombs land ~100 m ahead" defect and the permanent accuracy
## regression: with accuracy 1.0 and zero dispersion the reference bomb must
## land within a hull-sized tolerance of the ship.

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const STRIKE_MISSION: AirMissionData = preload(
	"res://resources/aircraft/missions/basic_dive_bombing.tres"
)
## Hull-scale pass thresholds (dd hull is ~150 m long, ~15 m wide).
const STATIC_TOLERANCE_M := 20.0
const MOVING_TOLERANCE_M := 30.0
const CROSSING_TOLERANCE_M := 35.0
const MAX_FRAMES := 3600

var _failures: Array[String] = []
var _released_projectiles: Array[WeakRef] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await _run_scenario("static", Vector3.ZERO, STATIC_TOLERANCE_M)
	await _run_scenario(
		"moving", Vector3(0.0, 0.0, 12.0), MOVING_TOLERANCE_M
	)
	await _run_scenario(
		"crossing", Vector3(12.0, 0.0, 0.0), CROSSING_TOLERANCE_M
	)
	print(
		"DIVE_BOMB_IMPACT_ACCURACY_TEST failures=%d" % _failures.size()
	)
	for failure in _failures:
		push_error("DIVE BOMB IMPACT ACCURACY: %s" % failure)
	quit(0 if _failures.is_empty() else 1)


func _run_scenario(
		label: String,
		target_velocity: Vector3,
		tolerance_m: float
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
		await _finish(battle)
		return
	# Constant-velocity target: physics off, integrated by the test so nothing
	# (AI, avoidance, waves) disturbs the motion the solver must predict.
	target.set_physics_process(false)
	target.velocity = target_velocity
	target.global_position = carrier.global_position \
		+ Vector3(0.0, 0.0, 2200.0)
	var squadron := carrier.carrier_air_group.launch_strike_squadron(
		"basic_bomber_squadron",
		target,
		STRIKE_MISSION
	)
	_check(squadron != null, label + ": strike squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	for aircraft in squadron.aircraft_units:
		aircraft.weapon_controller.weapon_released.connect(
			_on_weapon_released
		)
	var controller := squadron.dive_bomb_controller
	var reference_projectile: Projectile = null
	var reference_id := 0
	var impact_position := Vector3.INF
	var target_at_impact := Vector3.INF
	var attack_direction := Vector3.FORWARD
	var frames := 0
	var last_mission_state := "?"
	var last_controller_state := "?"
	var last_reason := "?"
	var physics_delta := 1.0 / float(Engine.physics_ticks_per_second)
	while frames < MAX_FRAMES:
		frames += 1
		if is_instance_valid(target):
			target.global_position += target_velocity * physics_delta
		await physics_frame
		if reference_id == 0 and is_instance_valid(squadron) \
				and controller.has_attack_solution:
			reference_id = controller.get_reference_aircraft_instance_id()
			attack_direction = controller.locked_attack_direction
		if reference_projectile == null and reference_id != 0:
			reference_projectile = _find_reference_projectile(reference_id)
		if reference_projectile != null \
				and is_instance_valid(reference_projectile) \
				and not reference_projectile.active:
			impact_position = reference_projectile.last_despawn_position
			target_at_impact = target.global_position \
				if is_instance_valid(target) else Vector3.INF
			break
		if is_instance_valid(squadron) \
				and squadron.mission_controller != null \
				and squadron.mission_controller.dive_bomb_behavior != null:
			last_mission_state = DiveBombMissionBehavior.State.keys()[int(
				squadron.mission_controller.dive_bomb_behavior.state
			)]
			last_controller_state = \
				DiveBombAttackController.State.keys()[int(controller.state)]
			last_reason = \
				DiveBombAttackController.ReleaseBlockReason.keys()[
					int(controller.release_block_reason)
				]
		if not is_instance_valid(squadron):
			break
	if not impact_position.is_finite():
		print(
			"TIMEOUT %s frames=%d mission=%s released=%d ref_id=%d"
			% [
				label,
				frames,
				last_mission_state + "/" + last_controller_state
					+ "/" + last_reason,
				_released_projectiles.size(),
				reference_id,
			]
		)
	_check(
		impact_position.is_finite() and target_at_impact.is_finite(),
		label + ": the reference bomb impacts within the frame budget"
	)
	if impact_position.is_finite() and target_at_impact.is_finite():
		var error := impact_position - target_at_impact
		error.y = 0.0
		var forward_error := error.dot(attack_direction)
		var lateral_error := error.dot(Vector3(
			-attack_direction.z, 0.0, attack_direction.x
		))
		var along_travel := error.dot(target_velocity.normalized()) \
			if target_velocity.length() > 0.1 else 0.0
		print(
			(
				"MEASURE %s impact_error_m=%.1f forward_m=%.1f "
				+ "lateral_m=%.1f along_target_travel_m=%.1f "
				+ "impact=%s target=%s"
			) % [
				label,
				error.length(),
				forward_error,
				lateral_error,
				along_travel,
				impact_position,
				target_at_impact,
			]
		)
		_check(
			error.length() <= tolerance_m,
			"%s: reference bomb lands within %.0f m of the ship (got %.1f m)"
				% [label, tolerance_m, error.length()]
		)
	await _finish(battle)


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
	# Tag at release time so the test can single out the reference bomb.
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
