extends SceneTree
## Weapon availability contracts (§34): a non-bomb payload is rejected, an
## aircraft without ammunition never gets a controller, and a weapon disabled
## mid-attack fails only that aircraft while returning its ownership.

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
	var dive_data := squadron.get_dive_bomber_combat_data()
	var weapon_data := squadron.get_aircraft_weapon_data()
	var aircraft := squadron.aircraft_units[0] as AircraftUnit
	var aim: Vector3 = aircraft.global_position + Vector3(0.0, 0.0, 1200.0)
	aim.y = 0.0
	var solution := DiveBombAttackPlanner.build_fixed_impact_solution(
		aircraft,
		aim,
		Vector3.ZERO,
		dive_data,
		weapon_data,
		DiveBombAttackContext.new()
	)
	_check(solution != null and solution.valid, "attack solution builds")

	# --- A torpedo loadout is not a bomb.
	var torpedo_data := load(
		"res://resources/aircraft/weapons/basic_torpedo_loadout.tres"
	) as AircraftWeaponData
	_check(torpedo_data != null, "torpedo loadout resource loads")
	var torpedo_controller := AircraftDiveBombController.new()
	_check(
		not torpedo_controller.setup(
			aircraft,
			torpedo_data,
			dive_data,
			solution
		),
		"a torpedo payload is rejected as a dive bomb"
	)
	_check(
		aircraft.is_movement_owned_by(AircraftMovementOwner.Type.FORMATION),
		"the rejected setup leaves no ownership behind"
	)

	# --- No ammunition: excluded from the attack entirely.
	var empty_aircraft := squadron.aircraft_units[1] as AircraftUnit
	empty_aircraft.weapon_controller.remaining_ammunition = 0
	var target_point := squadron.formation_center + Vector3(0.0, 0.0, 1500.0)
	target_point.y = 0.0
	var coordinator := DiveBombContractTestSupport.begin_quick_attack(
		squadron,
		DiveBombContractTestSupport.make_position_request(
			target_point,
			squadron.get_team()
		)
	)
	_check(coordinator != null, "quick attack coordinator starts")
	if coordinator == null:
		await _finish(battle)
		return
	var controllers := coordinator.get_aircraft_controllers()
	var empty_id := empty_aircraft.get_instance_id()
	for controller in controllers:
		_check(
			controller.attack_state.aircraft_instance_id != empty_id,
			"an aircraft without ammunition gets no controller"
		)
	_check(
		empty_aircraft.is_movement_owned_by(
			AircraftMovementOwner.Type.FORMATION
		),
		"the excluded aircraft stays under formation control"
	)

	# --- Weapon disabled during the attack: only that aircraft fails.
	_check(controllers.size() >= 2, "at least two attacking controllers")
	if controllers.size() >= 2:
		var disabled := controllers[0]
		var disabled_aircraft := disabled.attack_state.get_aircraft()
		disabled_aircraft.weapon_controller.disable_weapon_release()
		disabled_aircraft.weapon_controller.remaining_ammunition = 0
		DiveBombContractTestSupport.place_in_release_window(disabled)
		disabled.update(1.0 / 60.0)
		_check(
			disabled.attack_state.release_block_reason \
				== DiveBombReleaseBlockReason.Type.NO_AMMUNITION \
				or disabled.attack_state.release_block_reason \
					== DiveBombReleaseBlockReason.Type.WEAPON_DISABLED,
			"the disabled aircraft records its weapon failure"
		)
		_check(
			disabled.attack_state.state \
				== DiveBombAircraftAttackState.State.PULLING_OUT,
			"the disabled aircraft pulls out instead of stalling"
		)
		var healthy := controllers[1]
		DiveBombContractTestSupport.place_in_release_window(healthy)
		healthy.update(1.0 / 60.0)
		_check(
			healthy.attack_state.released,
			"other aircraft attack normally around the disabled one"
		)
	coordinator.cancel(&"test_finished")
	for unit in squadron.aircraft_units:
		_check(
			unit.is_movement_owned_by(
				AircraftMovementOwner.Type.FORMATION
			),
			"every aircraft is back under formation control"
		)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_WEAPON_UNAVAILABLE_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
