extends SceneTree
## A ship the player clicked directly stays the target even when another
## hostile ship sits closer to the designated point.

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
	var clicked := _find_hostile_ship(battle, carrier)
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null and clicked != null, "scenario spawns")
	if squadron == null or clicked == null:
		await _finish(battle)
		return
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	clicked.set_physics_process(false)
	clicked.global_position = Vector3(0.0, 0.0, 3000.0)
	# A second hostile ship much closer to the click point than the clicked
	# ship itself; registered so radius acquisition could see it.
	var nearer := DiveBombTargetingTestSupport.spawn_ship(
		root, &"enemy", clicked.global_position + Vector3(40.0, 0.0, 0.0)
	)
	squadron.battle_services.ship_registry.register_ship(nearer)
	var designation := nearer.global_position + Vector3(5.0, 0.0, 0.0)
	designation.y = 0.0
	_check(
		squadron.issue_player_move_command(Vector3.ZERO, null),
		"player takes command"
	)
	_check(
		squadron.begin_manual_dive_at(designation, 30.0, clicked),
		"clicked-ship order starts a player dive run"
	)
	var run := squadron._player_dive_run
	var resolved := run.get_resolved_target() if run != null else null
	_check(
		resolved != null and resolved.get_ship() == clicked,
		"the clicked ship wins over a nearer hostile ship"
	)
	_check(
		resolved != null and resolved.resolution_reason == &"explicit_target",
		"the selection is explicit, not radius-based"
	)
	# Repath re-resolution must not drift to the nearer ship either.
	if run != null:
		run.update(0.5)
		_check(
			run.get_resolved_target().get_ship() == clicked,
			"repath re-resolution keeps the explicit ship"
		)
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
		push_error("PLAYER EXPLICIT PRIORITY: %s" % failure)
	print(
		"DIVE_BOMB_PLAYER_EXPLICIT_TARGET_PRIORITY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
