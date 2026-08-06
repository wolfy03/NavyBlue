extends SceneTree
## Additional pass contract (§33): the attack pass index feeds the
## deterministic accuracy seed (each pass rolls its own offset, the same pass
## always rolls the same offset), and aircraft without ammunition are
## excluded from a later pass.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := DiveBombContractTestSupport.spawn_battle(root)
	await physics_frame
	var squadron := DiveBombContractTestSupport.launch_frozen_squadron(battle)
	_check(squadron != null, "squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	var target := _find_enemy(battle)
	_check(target != null, "a hostile target exists")
	if target == null:
		await _finish(battle)
		return
	target.set_physics_process(false)
	target.global_position = squadron.formation_center \
		+ Vector3(0.0, 0.0, 1500.0)
	target.global_position.y = 0.0

	# --- Pass index is folded into the deterministic accuracy seed.
	var dive_data := squadron.get_dive_bomber_combat_data() \
		.duplicate(true) as DiveBomberCombatData
	var imperfect := DiveBombAccuracyProfile.new()
	imperfect.base_accuracy = 0.3
	dive_data.accuracy_profile = imperfect
	var resolved := DiveBombTargetResolver.resolve(
		DiveBombContractTestSupport.make_ship_request(
			target,
			squadron.get_team()
		),
		squadron.get_dive_bomb_candidate_ships()
	)
	_check(
		resolved != null and resolved.is_valid(),
		"the target resolves"
	)
	var offsets: Array[Vector3] = []
	for pass_index in [1, 2, 1]:
		var context := DiveBombAttackContext.new()
		context.squadron_combat_id = CombatIdentity.for_squadron(squadron)
		context.attack_pass_index = pass_index
		DiveBombAttackPlanner.ensure_pass_dispersion(
			context,
			resolved,
			dive_data
		)
		offsets.append(context.pass_dispersion_offset)
	_check(
		offsets[0] != offsets[1],
		"a different pass index rolls a different accuracy offset"
	)
	_check(
		offsets[0] == offsets[2],
		"the same pass index always rolls the same offset"
	)

	# --- A second-pass coordinator excludes ammunition-less aircraft.
	var empty_aircraft := squadron.aircraft_units[0] as AircraftUnit
	empty_aircraft.weapon_controller.remaining_ammunition = 0
	var coordinator := SquadronDiveBombCoordinator.new()
	_check(
		coordinator.setup(
			squadron,
			DiveBombContractTestSupport.make_ship_request(
				target,
				squadron.get_team()
			),
			DiveBombAttackMode.Type.QUICK_ATTACK,
			2
		),
		"a pass-2 coordinator starts"
	)
	coordinator.update(0.0)
	var controllers := coordinator.get_aircraft_controllers()
	_check(
		controllers.size() \
			== squadron.get_alive_aircraft().size() - 1,
		"the empty aircraft is excluded from the later pass"
	)
	for controller in controllers:
		_check(
			controller.attack_state.aircraft_instance_id \
				!= empty_aircraft.get_instance_id(),
			"no controller drives the ammunition-less aircraft"
		)
	coordinator.cancel(&"test_finished")
	await _finish(battle)


func _find_enemy(battle: BattleScene) -> ShipUnit:
	for ship_value in battle.enemies:
		var ship := ship_value as ShipUnit
		if ship != null and is_instance_valid(ship):
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_ADDITIONAL_PASS_COUNT_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
