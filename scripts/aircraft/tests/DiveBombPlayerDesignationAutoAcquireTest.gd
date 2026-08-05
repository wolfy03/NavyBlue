extends SceneTree
## Player dive-bomb designation on open water near a hostile ship: the ship
## inside the acquisition radius becomes the actual attack target and the
## run's entry waypoint tracks it.

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
	enemy.velocity = Vector3(8.0, 0.0, 0.0)
	# Ocean click 150 m from the ship: inside the 250 m acquisition radius.
	var designation := enemy.global_position + Vector3(150.0, 0.0, 0.0)
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
	_check(run != null, "the run is registered on the squadron")
	if run == null:
		await _finish(battle)
		return
	var resolved := run.get_resolved_target()
	_check(
		resolved != null and resolved.get_ship() == enemy,
		"the hostile ship inside the radius is auto-acquired"
	)
	_check(
		resolved.resolution_reason == &"radius_acquired",
		"the acquisition is radius-based, not explicit"
	)
	run.update(0.0)
	var first_destination := squadron.destination
	# The entry waypoint must track the ship, not the clicked point: move the
	# ship far enough to force an entry repath.
	enemy.global_position += Vector3(0.0, 0.0, 400.0)
	run.update(0.5)
	_check(
		squadron.destination != first_destination,
		"the entry waypoint follows the acquired ship"
	)
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
		push_error("PLAYER AUTO ACQUIRE: %s" % failure)
	print(
		"DIVE_BOMB_PLAYER_DESIGNATION_AUTO_ACQUIRE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
