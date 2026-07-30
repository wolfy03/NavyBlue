extends SceneTree

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
	var carrier := battle.player_ship as ShipUnit
	var target := _find_hostile_ship(battle, carrier)
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(
		squadron != null and target != null,
		"AI approach test has a squadron and target"
	)
	if squadron == null or target == null:
		await _finish(battle)
		return
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	target.set_physics_process(false)
	target.velocity = Vector3.ZERO
	var behavior := DiveBombMissionBehavior.new()
	_check(
		behavior.setup(squadron, target, STRIKE_MISSION),
		"AI dive behavior setup succeeds"
	)
	behavior.update(0.0)
	var first_approach := squadron.destination
	target.global_position.x += 100.0
	behavior._approach_repath_left = 0.0
	behavior.update(0.5)
	_check(
		squadron.destination == first_approach,
		"sub-threshold target movement does not reset approach"
	)
	target.global_position.x += 200.0
	behavior._approach_repath_left = 0.0
	behavior.update(0.5)
	_check(
		squadron.destination != first_approach,
		"large target movement repaths the approach"
	)
	squadron._mission_destination_reached = true
	behavior.update(0.0)
	_check(
		behavior.state == DiveBombMissionBehavior.State.DIVE_ENTRY,
		"approach arrival advances to fixed dive entry"
	)
	behavior.update(0.0)
	var fixed_entry := squadron.destination
	target.global_position.x += 500.0
	behavior.update(0.5)
	_check(
		squadron.destination == fixed_entry,
		"dive entry destination remains fixed while target moves"
	)
	var controller := squadron.dive_bomb_controller
	_check(
		controller.begin_dive_with_source(
			target.global_position,
			target.velocity,
			AircraftSquadron.DiveControlSource.AI
		) == DiveBombAttackController.BeginDiveResult.STARTED,
		"AI controller can be pre-started"
	)
	squadron._mission_destination_reached = true
	behavior.update(0.0)
	_check(
		behavior.state == DiveBombMissionBehavior.State.DIVING,
		"same-source active controller advances instead of failing"
	)
	controller.cancel()
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
		push_error("DIVE BOMB AI APPROACH REPATH TEST: %s" % failure)
	print(
		"DIVE_BOMB_AI_APPROACH_REPATH_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
