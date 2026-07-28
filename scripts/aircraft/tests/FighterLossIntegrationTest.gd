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
	var target_squadron := enemy.carrier_air_group.launch_squadron(
		"basic_bomber_squadron",
		Vector3.ZERO
	)
	var fighter_squadron := player.carrier_air_group \
		.launch_intercept_squadron(
			"basic_fighter_squadron",
			target_squadron
		)
	if fighter_squadron == null or target_squadron == null:
		_check(false, "combat squadrons launch")
		await _finish(battle)
		return
	var attacker := fighter_squadron.aircraft_units[0]
	var target := target_squadron.aircraft_units[0]
	attacker.activate()
	target.activate()
	attacker.global_position = Vector3(0.0, 220.0, 300.0)
	target.global_position = Vector3(0.0, 220.0, 0.0)
	attacker.global_transform.basis = Basis.looking_at(
		Vector3.FORWARD,
		Vector3.UP
	)
	var controller := attacker.fighter_combat_controller
	controller.fighter_data = controller.fighter_data.duplicate(
		true
	) as FighterCombatData
	controller.fighter_data.base_accuracy = 1.0
	controller.fighter_data.minimum_accuracy = 1.0
	controller.fighter_data.maximum_accuracy = 1.0
	controller.fighter_data.target_evasion_weight = 0.0
	controller.fighter_data.lock_time_sec = 0.0
	controller.gun_data = controller.gun_data.duplicate(true) \
		as AircraftGunData
	controller.gun_data.mechanical_accuracy = 1.0
	controller.gun_data.damage_per_hit = 100.0
	controller.set_target(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var result := controller.update_combat(0.1, rng)
	_check(
		result.hit_count == result.rounds_fired \
			and result.total_damage > 0.0,
		"gun burst resolves lethal AircraftHealth damage"
	)
	await process_frame
	await process_frame
	var state := enemy.carrier_air_group.get_squadron_state(
		"basic_bomber_squadron"
	)
	_check(
		state.active_aircraft == 3 and state.lost_aircraft == 1,
		"aircraft destruction updates CarrierAirGroup loss state"
	)
	var surviving_target := target_squadron.aircraft_units[1]
	surviving_target.activate()
	attacker.global_position = Vector3(0.0, 220.0, 300.0)
	surviving_target.global_position = Vector3(0.0, 220.0, 0.0)
	controller.set_target(surviving_target)
	var ammunition_before_loss := attacker.weapon_controller \
		.get_remaining_ammunition()
	player.carrier_air_group.resolve_carrier_loss()
	var blocked_result := controller.update_combat(1.0, rng)
	_check(
		blocked_result.rounds_fired == 0 \
			and attacker.weapon_controller.get_remaining_ammunition() \
				== ammunition_before_loss,
		"carrier loss blocks additional fighter gun damage"
	)
	var coordinator := fighter_squadron.get_combat_coordinator()
	_check(
		coordinator == null \
			or coordinator.get_interceptor_count_for(target_squadron) == 0,
		"carrier loss clears the intercept assignment"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("FIGHTER LOSS INTEGRATION TEST: %s" % failure)
	print(
		"FIGHTER_LOSS_INTEGRATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
