extends SceneTree
## AI target destroyed during the approach: the mission re-searches around
## the designation, switches to a surviving hostile ship when one is there,
## and falls back to the position when none is.

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
	var replacement := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", assigned.global_position + Vector3(120.0, 0.0, 0.0)
	)
	squadron.battle_services.ship_registry.register_ship(replacement)
	var behavior := DiveBombMissionBehavior.new()
	_check(
		behavior.setup(squadron, assigned, STRIKE_MISSION),
		"explicit AI strike sets up"
	)
	behavior.update(0.0)
	# The assigned ship sinks mid-approach.
	assigned._is_sinking = true
	behavior._approach_repath_left = 0.0
	behavior.update(0.5)
	_check(
		behavior.state == DiveBombMissionBehavior.State.APPROACHING,
		"the mission keeps approaching after the loss"
	)
	_check(
		behavior.get_resolved_target().get_ship() == replacement,
		"a surviving ship near the designation is reacquired"
	)
	_check(
		behavior.get_debug_snapshot().get("target_reacquire_count", 0) >= 1,
		"the reacquisition is counted"
	)
	# The replacement sinks too: a ship strike with nothing left to attack
	# fails safely and returns instead of bombing empty water.
	replacement._is_sinking = true
	behavior._approach_repath_left = 0.0
	behavior.update(0.5)
	_check(
		behavior.is_finished() \
			and behavior.state == DiveBombMissionBehavior.State.RETURNING,
		"losing every ship fails the ship strike safely"
	)
	# A position-designated AI request keeps the fallback: the same double
	# loss ends in a WORLD_POSITION target instead of a mission failure.
	var lost_a := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", Vector3(500.0, 0.0, 500.0)
	)
	squadron.battle_services.ship_registry.register_ship(lost_a)
	var position_request := DiveBombTargetRequest.new()
	position_request.source = DiveBombTargetRequest.Source.AI
	position_request.designated_world_position = lost_a.global_position
	position_request.acquisition_radius_m = 250.0
	position_request.requesting_team = squadron.get_team()
	position_request.allow_position_fallback = true
	var position_behavior := DiveBombMissionBehavior.new()
	_check(
		position_behavior.setup_with_request(
			squadron, position_request, STRIKE_MISSION
		),
		"position-designated AI request sets up"
	)
	position_behavior.update(0.0)
	lost_a._is_sinking = true
	position_behavior._approach_repath_left = 0.0
	position_behavior.update(0.5)
	_check(
		position_behavior.get_resolved_target() != null \
			and position_behavior.get_resolved_target().type \
				== DiveBombResolvedTarget.TargetType.WORLD_POSITION,
		"a position-designated strike falls back to the position"
	)
	_check(
		not position_behavior.is_finished(),
		"the position fallback keeps the area strike running"
	)
	position_behavior.cancel_without_return()
	lost_a.queue_free()
	behavior.cancel_without_return()
	replacement.queue_free()
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
		push_error("AI APPROACH LOSS: %s" % failure)
	print(
		"DIVE_BOMB_AI_TARGET_DESTROYED_DURING_APPROACH_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
