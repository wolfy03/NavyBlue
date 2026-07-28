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
	var target := enemy.carrier_air_group.launch_squadron(
		"basic_bomber_squadron",
		player.global_position
	)
	var fighter := player.carrier_air_group.launch_intercept_squadron(
		"basic_fighter_squadron",
		target
	)
	_check(fighter != null and target != null, "intercept mission launches")
	if fighter != null:
		var coordinator := fighter.get_combat_coordinator()
		_check(
			int(coordinator.get_debug_snapshot().get(
				"intercept_assignments",
				{}
			).size()) == 1,
			"intercept assignment is registered"
		)
		_check(
			fighter.issue_player_move_command(
				player.global_position + Vector3(600.0, 0.0, 0.0)
			),
			"player move overrides intercept mission"
		)
		_check(
			fighter.is_player_commanded() \
				and fighter.get_current_target() == null,
			"manual command clears intercept target"
		)
		_check(
			int(coordinator.get_debug_snapshot().get(
				"intercept_assignments",
				{}
			).size()) == 0,
			"manual command removes coordinator assignment"
		)
	player.carrier_air_group.launch_cooldown_left = 0.0
	var bomber := player.carrier_air_group.launch_strike_squadron(
		"basic_bomber_squadron",
		enemy
	)
	_check(bomber != null, "strike mission launches")
	if bomber != null:
		_check(
			bomber.issue_player_move_command(
				player.global_position + Vector3(-600.0, 0.0, 0.0)
			),
			"player move overrides strike mission"
		)
		_check(
			bomber.mission_controller.mission_data == null \
				and bomber.get_current_target() == null,
			"manual command clears ship strike state"
		)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("PLAYER MISSION CANCELLATION TEST: %s" % failure)
	print(
		"PLAYER_MISSION_CANCELLATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
