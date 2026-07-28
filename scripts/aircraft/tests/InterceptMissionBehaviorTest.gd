extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/fighter_combat_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	var player := FighterTestSupport.find_carrier(
		battle,
		FactionRelations.PLAYER
	)
	var enemy := FighterTestSupport.find_carrier(
		battle,
		FactionRelations.ENEMY
	)
	FighterTestSupport.stop_carrier_ai(enemy)
	if player == null or enemy == null:
		_check(false, "test carriers exist")
		await _finish(battle)
		return
	var target := enemy.carrier_air_group.launch_squadron(
		"basic_bomber_squadron",
		Vector3.ZERO
	)
	var fighter := player.carrier_air_group.launch_intercept_squadron(
		"basic_fighter_squadron",
		target
	)
	_check(fighter != null and target != null, "intercept mission launches")
	if fighter != null and target != null:
		fighter.set_physics_process(false)
		target.set_physics_process(false)
		fighter.formation_center = Vector3(0.0, 220.0, 300.0)
		target.formation_center = Vector3(0.0, 220.0, 0.0)
		for aircraft in fighter.aircraft_units:
			aircraft.activate()
			aircraft.global_position = Vector3(0.0, 220.0, 300.0)
			aircraft.global_transform.basis = Basis.looking_at(
				Vector3.FORWARD,
				Vector3.UP
			)
		for aircraft in target.aircraft_units:
			aircraft.activate()
			aircraft.global_position = Vector3(0.0, 220.0, 0.0)
		var behavior := fighter.mission_controller.intercept_behavior \
			as InterceptMissionBehavior
		_check(behavior != null, "mission controller owns intercept behavior")
		if behavior != null:
			behavior.update(0.1)
			behavior.update(0.1)
			var ammo_before := fighter.aircraft_units[0] \
				.weapon_controller.get_remaining_ammunition()
			behavior.update(0.7)
			var ammo_after := fighter.aircraft_units[0] \
				.weapon_controller.get_remaining_ammunition()
			_check(
				behavior.get_state() \
					== InterceptMissionBehavior.State.SEPARATING,
				"intercept behavior performs firing pass then separates"
			)
			_check(ammo_after < ammo_before, "firing pass consumes gun ammo")
			_check(
				fighter.get_current_target() == target,
				"intercept target remains distinct from ship target"
			)
			target.formation_center = player.global_position \
				+ Vector3(9000.0, 220.0, 0.0)
			behavior.update(0.1)
			_check(
				behavior.is_finished() \
					and fighter.state \
						== AircraftSquadron.State.RETURNING,
				"target leaving combat radius ends intercept and returns"
			)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("INTERCEPT MISSION BEHAVIOR TEST: %s" % failure)
	print(
		"INTERCEPT_MISSION_BEHAVIOR_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
