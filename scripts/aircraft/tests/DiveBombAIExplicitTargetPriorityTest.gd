extends SceneTree
## An AI mission assigned a specific ship keeps that ship even when another
## hostile ship is closer, including across approach repath re-resolutions.

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
	# A second hostile ship right next to the assigned one (well inside the
	# acquisition radius), registered as a candidate.
	var nearer := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", assigned.global_position + Vector3(30.0, 0.0, 0.0)
	)
	squadron.battle_services.ship_registry.register_ship(nearer)
	var behavior := DiveBombMissionBehavior.new()
	_check(
		behavior.setup(squadron, assigned, STRIKE_MISSION),
		"explicit AI strike sets up"
	)
	var resolved := behavior.get_resolved_target()
	_check(
		resolved != null and resolved.get_ship() == assigned,
		"the assigned ship is the resolved target"
	)
	behavior.update(0.0)
	behavior._approach_repath_left = 0.0
	behavior.update(0.5)
	_check(
		behavior.get_resolved_target().get_ship() == assigned,
		"repath re-resolution keeps the assigned ship"
	)
	behavior.cancel_without_return()
	nearer.queue_free()
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
		push_error("AI EXPLICIT PRIORITY: %s" % failure)
	print(
		"DIVE_BOMB_AI_EXPLICIT_TARGET_PRIORITY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
