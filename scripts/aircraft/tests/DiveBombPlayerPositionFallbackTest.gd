extends SceneTree
## Player designation on empty water (no hostile ship inside the radius):
## the run attacks the designated position itself with zero target velocity.

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
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null, "squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
	# Inside the squadron's combat radius but far from every stage ship:
	# nothing inside the 250 m acquisition radius.
	var designation := carrier.global_position + Vector3(1500.0, 0.0, -1500.0)
	designation.y = 0.0
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship == null:
			continue
		var offset := ship.global_position - designation
		offset.y = 0.0
		_check(
			offset.length() > 250.0,
			"precondition: no ship inside the acquisition radius"
		)
	_check(
		squadron.issue_player_move_command(Vector3.ZERO, null),
		"player takes command"
	)
	_check(
		squadron.begin_manual_dive_at(designation, 30.0, null),
		"empty-water order starts a player dive run"
	)
	var run := squadron._player_dive_run
	var resolved := run.get_resolved_target() if run != null else null
	_check(
		resolved != null \
			and resolved.type \
				== DiveBombResolvedTarget.TargetType.WORLD_POSITION,
		"no ship in the radius falls back to the position"
	)
	_check(
		resolved != null \
			and resolved.get_aim_position() == designation \
			and resolved.get_target_velocity() == Vector3.ZERO,
		"the fallback aims at the designation with zero velocity"
	)
	if run != null:
		run.update(0.0)
		var entry := squadron.destination
		var to_designation := entry - designation
		to_designation.y = 0.0
		_check(
			to_designation.length() < 1500.0,
			"the entry waypoint is planned around the designated point"
		)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("PLAYER POSITION FALLBACK: %s" % failure)
	print(
		"DIVE_BOMB_PLAYER_POSITION_FALLBACK_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
