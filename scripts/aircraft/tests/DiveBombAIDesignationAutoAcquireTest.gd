extends SceneTree
## AI world-position strike request: a hostile ship inside the acquisition
## radius around the designation becomes the actual mission target.

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
	var behavior := DiveBombMissionBehavior.new()
	# Position-based AI request: no explicit ship, designation 150 m off.
	var request := DiveBombTargetRequest.new()
	request.source = DiveBombTargetRequest.Source.AI
	request.designated_world_position = enemy.global_position \
		+ Vector3(150.0, 0.0, 0.0)
	request.designated_world_position.y = 0.0
	request.acquisition_radius_m = 250.0
	request.requesting_team = squadron.get_team()
	request.allow_position_fallback = true
	_check(
		behavior.setup_with_request(squadron, request, STRIKE_MISSION),
		"position-based AI request sets up"
	)
	var resolved := behavior.get_resolved_target()
	_check(
		resolved != null and resolved.get_ship() == enemy,
		"the hostile ship inside the radius is acquired"
	)
	_check(
		resolved != null and resolved.resolution_reason == &"radius_acquired",
		"the acquisition is radius-based"
	)
	behavior.update(0.0)
	_check(
		behavior.state == DiveBombMissionBehavior.State.APPROACHING,
		"the mission approaches the acquired ship"
	)
	var snapshot := behavior.get_debug_snapshot()
	_check(
		String(snapshot.get("resolved_target_type", "")) == "SHIP",
		"the debug snapshot reports a ship target"
	)
	_check(
		snapshot.get("target_resolve_count", 0) >= 1,
		"the debug snapshot counts resolver runs"
	)
	behavior.cancel_without_return()
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
		push_error("AI AUTO ACQUIRE: %s" % failure)
	print(
		"DIVE_BOMB_AI_DESIGNATION_AUTO_ACQUIRE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
