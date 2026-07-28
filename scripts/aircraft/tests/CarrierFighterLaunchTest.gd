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
	var enemy_bomber := enemy.carrier_air_group.launch_squadron(
		"basic_bomber_squadron",
		player.global_position
	)
	var fighter_ids := player.carrier_air_group \
		.get_launchable_fighter_squadron_ids()
	_check(
		fighter_ids == ["basic_fighter_squadron"],
		"carrier exposes only ready fighter squadron"
	)
	var fighter := player.carrier_air_group.launch_intercept_squadron(
		"basic_fighter_squadron",
		enemy_bomber
	)
	_check(fighter != null, "carrier launches intercept squadron")
	if fighter != null:
		_check(
			fighter.get_aircraft_role() \
				== AircraftData.AircraftRole.FIGHTER \
				and fighter.get_current_target() == enemy_bomber,
			"intercept mission targets hostile aircraft squadron"
		)
		_check(
			fighter.aircraft_units.size() == 4 \
				and fighter.aircraft_units[0] \
					.fighter_combat_controller != null,
			"fighter sortie uses existing four-aircraft lifecycle"
		)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER FIGHTER LAUNCH TEST: %s" % failure)
	print(
		"CARRIER_FIGHTER_LAUNCH_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
