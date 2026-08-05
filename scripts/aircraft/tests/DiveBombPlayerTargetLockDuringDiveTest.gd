extends SceneTree
## Once a player dive has committed, the solution is locked: a hostile ship
## appearing closer to the aim point never changes the attack.

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await physics_frame
	var carrier := battle.player_ship as ShipUnit
	var enemy := _find_hostile_ship(battle, carrier)
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null and enemy != null, "scenario spawns")
	if squadron == null or enemy == null:
		await _finish(battle)
		return
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(0.0, 0.0, 3000.0)
	enemy.velocity = Vector3.ZERO
	var designation := enemy.global_position + Vector3(100.0, 0.0, 0.0)
	designation.y = 0.0
	_check(
		squadron.issue_player_move_command(Vector3.ZERO, null),
		"player takes command"
	)
	_check(
		squadron.begin_manual_dive_at(designation, 30.0, null),
		"designation order starts a player dive run"
	)
	var run := squadron._player_dive_run
	if run == null:
		_check(false, "run exists")
		await _finish(battle)
		return
	# Put the whole squadron at dive-entry altitude close to the ship so the
	# distance gate commits on the first update.
	squadron.formation_center = enemy.global_position \
		+ Vector3(0.0, 350.0, -100.0)
	squadron._formation_forward = Vector3(0.0, 0.0, 1.0)
	for aircraft in squadron.get_alive_aircraft():
		aircraft.global_position = squadron.formation_center \
			+ aircraft.formation_offset * 0.01
		aircraft.velocity = Vector3(0.0, 0.0, 120.0)
	run.update(0.0)
	var controller := squadron.dive_bomb_controller
	_check(
		run.state == PlayerDiveBombRun.State.DIVING \
			and controller.is_active(),
		"the distance gate commits the player dive"
	)
	_check(
		controller.is_solution_locked(),
		"a committed player dive locks its solution"
	)
	var locked_impact := controller.predicted_impact_position
	var locked_direction := controller.locked_attack_direction
	_check(
		locked_impact.distance_to(enemy.global_position) < 60.0,
		"the locked impact aims at the acquired ship"
	)
	# A new hostile ship appears even closer to the aim point mid-dive.
	var intruder := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", enemy.global_position + Vector3(20.0, 0.0, 0.0)
	)
	squadron.battle_services.ship_registry.register_ship(intruder)
	controller.update_dive(1.0 / 60.0)
	squadron._update_player_dive_target()
	_check(
		controller.predicted_impact_position == locked_impact,
		"a closer ship mid-dive never moves the locked impact"
	)
	_check(
		controller.locked_attack_direction == locked_direction,
		"a closer ship mid-dive never bends the locked heading"
	)
	controller.cancel()
	intruder.queue_free()
	await _finish(battle)


func _find_hostile_ship(
		battle: BattleScene,
		carrier: ShipUnit
) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null and carrier.is_hostile_to(ship):
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("PLAYER TARGET LOCK: %s" % failure)
	print(
		"DIVE_BOMB_PLAYER_TARGET_LOCK_DURING_DIVE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
