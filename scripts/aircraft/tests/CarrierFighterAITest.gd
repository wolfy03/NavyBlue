extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/fighter_carrier_ai_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	var ally := FighterTestSupport.find_carrier(
		battle,
		FactionRelations.ALLY
	)
	var enemy := FighterTestSupport.find_carrier(
		battle,
		FactionRelations.ENEMY
	)
	FighterTestSupport.stop_carrier_ai(ally)
	FighterTestSupport.stop_carrier_ai(enemy)
	if ally == null or enemy == null:
		_check(false, "AI test carriers exist")
		await _finish(battle)
		return
	_check(
		_count_active_fighters(ally.carrier_air_group) == 0,
		"fighter is not launched without hostile aircraft"
	)
	var enemy_bomber := enemy.carrier_air_group.launch_squadron(
		"basic_bomber_squadron",
		ally.global_position
	)
	_check(enemy_bomber != null, "enemy bomber threat launches")
	ally.carrier_air_group.launch_cooldown_left = 0.0
	ally.carrier_air_group_ai.setup(
		ally,
		ally.carrier_air_group
	)
	ally.carrier_air_group_ai.update_ai(2.0)
	var interceptor := _find_active_fighter(ally.carrier_air_group)
	_check(
		interceptor != null,
		"AI carrier prioritizes fighter against hostile air squadron"
	)
	if interceptor != null:
		_check(
			interceptor.get_current_target() == enemy_bomber,
			"AI interceptor receives detected bomber target"
		)
	_check(
		ally.carrier_air_group.get_active_squadron_count() == 1,
		"AI launches at most one squadron per decision tick"
	)
	await _finish(battle)


func _find_active_fighter(
		group: CarrierAirGroup
) -> AircraftSquadron:
	for squadron in group.get_active_squadrons():
		if squadron.get_aircraft_role() \
				== AircraftData.AircraftRole.FIGHTER:
			return squadron
	return null


func _count_active_fighters(group: CarrierAirGroup) -> int:
	var count := 0
	for squadron in group.get_active_squadrons():
		if squadron.get_aircraft_role() \
				== AircraftData.AircraftRole.FIGHTER:
			count += 1
	return count


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER FIGHTER AI TEST: %s" % failure)
	print(
		"CARRIER_FIGHTER_AI_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
