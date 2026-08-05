extends SceneTree
## AI target destroyed after the dive has committed: the locked solution is
## kept — no swerve toward a new ship, no impact-point change, and the
## mission does not abandon the attack.

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const STRIKE_MISSION: AirMissionData = preload(
	"res://resources/aircraft/missions/basic_dive_bombing.tres"
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
	var assigned := _find_hostile_ship(battle, carrier)
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null and assigned != null, "scenario spawns")
	if squadron == null or assigned == null:
		await _finish(battle)
		return
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	assigned.set_physics_process(false)
	assigned.global_position = Vector3(0.0, 0.0, 3000.0)
	assigned.velocity = Vector3.ZERO
	var behavior := DiveBombMissionBehavior.new()
	_check(
		behavior.setup(squadron, assigned, STRIKE_MISSION),
		"explicit AI strike sets up"
	)
	# Put the squadron at commit range so the distance gate starts the dive.
	squadron.formation_center = assigned.global_position \
		+ Vector3(0.0, 350.0, -100.0)
	squadron._formation_forward = Vector3(0.0, 0.0, 1.0)
	for aircraft in squadron.get_alive_aircraft():
		aircraft.global_position = squadron.formation_center \
			+ aircraft.formation_offset * 0.01
		aircraft.velocity = Vector3(0.0, 0.0, 120.0)
	behavior.update(0.0)
	squadron.destination_tracker.mark_reached(
		behavior._active_destination_serial
	)
	behavior.update(0.0)
	_check(
		behavior.state == DiveBombMissionBehavior.State.DIVE_ENTRY,
		"approach arrival advances to dive entry"
	)
	behavior.update(0.0)
	_check(
		behavior.state == DiveBombMissionBehavior.State.DIVING,
		"the distance gate commits the dive"
	)
	var controller := squadron.dive_bomb_controller
	# The AI locks its solution on the first DIVING update.
	behavior.update(0.0)
	_check(
		controller.is_solution_locked(),
		"the committed AI dive locks its solution"
	)
	var locked_impact := controller.predicted_impact_position
	var locked_direction := controller.locked_attack_direction
	# The target sinks mid-dive; another hostile ship appears nearby.
	assigned._is_sinking = true
	var intruder := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", locked_impact + Vector3(30.0, 0.0, 0.0)
	)
	squadron.battle_services.ship_registry.register_ship(intruder)
	behavior.update(0.0)
	_check(
		behavior.state == DiveBombMissionBehavior.State.DIVING \
			and not behavior.is_finished(),
		"losing the ship mid-dive never abandons the committed attack"
	)
	_check(
		controller.predicted_impact_position == locked_impact,
		"the locked impact point survives the target loss"
	)
	_check(
		controller.locked_attack_direction == locked_direction,
		"the locked heading survives the target loss"
	)
	var resolved := behavior.get_resolved_target()
	_check(
		resolved != null and resolved.get_ship() == null,
		"no new ship is adopted mid-dive"
	)
	behavior.cancel_without_return()
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
		push_error("AI DIVE LOSS: %s" % failure)
	print(
		"DIVE_BOMB_AI_TARGET_DESTROYED_DURING_DIVE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
