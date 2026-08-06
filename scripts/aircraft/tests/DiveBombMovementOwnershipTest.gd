extends SceneTree
## Movement ownership contracts (§7, §11-13, §29): atomic setup, idempotent
## release, lifecycle force-override, and stale-controller lockout via the
## ownership generation.

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
	var aircraft := squadron.aircraft_units[0] as AircraftUnit
	var dive_data := squadron.get_dive_bomber_combat_data()
	var weapon_data := squadron.get_aircraft_weapon_data()
	var context := DiveBombAttackContext.new()
	var aim: Vector3 = aircraft.global_position + Vector3(0.0, 0.0, 1200.0)
	aim.y = 0.0
	var solution := DiveBombAttackPlanner.build_fixed_impact_solution(
		aircraft,
		aim,
		Vector3.ZERO,
		dive_data,
		weapon_data,
		context
	)
	_check(solution != null and solution.valid, "attack solution builds")

	# --- Failed setup validation never takes ownership.
	var rejected := AircraftDiveBombController.new()
	_check(
		not rejected.setup(aircraft, null, dive_data, solution),
		"setup rejects missing weapon data"
	)
	_check(
		aircraft.is_movement_owned_by(AircraftMovementOwner.Type.FORMATION),
		"a rejected setup leaves the aircraft with FORMATION"
	)

	# --- Successful setup owns movement, with reason and generation.
	var controller := AircraftDiveBombController.new()
	_check(
		controller.setup(aircraft, weapon_data, dive_data, solution),
		"valid setup succeeds"
	)
	_check(
		aircraft.is_movement_owned_by(
			AircraftMovementOwner.Type.DIVE_BOMB_ATTACK
		),
		"setup acquires DIVE_BOMB_ATTACK ownership"
	)
	var generation_at_acquire := aircraft.movement_owner_generation
	_check(
		aircraft.movement_owner_reason == &"dive_bomb_setup",
		"the acquire reason is recorded"
	)

	# --- A second attack system cannot steal the aircraft.
	_check(
		not aircraft.acquire_movement_owner(
			AircraftMovementOwner.Type.TORPEDO_ATTACK,
			&"conflict"
		),
		"a competing combat system cannot steal ownership"
	)

	# --- Lifecycle force-override recovers the aircraft and locks the
	# stale controller out through the generation.
	aircraft.force_release_movement_owner(&"return_requested")
	_check(
		aircraft.is_movement_owned_by(AircraftMovementOwner.Type.FORMATION),
		"the lifecycle override returns the aircraft to FORMATION"
	)
	_check(
		aircraft.movement_owner_generation > generation_at_acquire,
		"the override advances the ownership generation"
	)
	_check(
		not aircraft.set_direct_flight_owned(
			Vector3.FORWARD,
			100.0,
			AircraftMovementOwner.Type.DIVE_BOMB_ATTACK
		),
		"a stale controller cannot apply direct flight after the override"
	)
	controller.attack_state.state = DiveBombAircraftAttackState.State.DIVING
	controller.update(1.0 / 60.0)
	_check(
		controller.attack_state.state \
			== DiveBombAircraftAttackState.State.FAILED \
			and controller.attack_state.release_block_reason \
				== DiveBombReleaseBlockReason.Type.MOVEMENT_OWNERSHIP_LOST,
		"the stale controller fails itself on the next update"
	)

	# --- release is idempotent from every path.
	controller.release_movement_ownership(&"cleanup")
	controller.release_movement_ownership(&"cleanup_again")
	controller.cancel(&"late_cancel")
	_check(
		aircraft.is_movement_owned_by(AircraftMovementOwner.Type.FORMATION),
		"repeated releases and late cancels stay safe"
	)

	# --- Squadron-level lifecycle recovery.
	var second := AircraftDiveBombController.new()
	_check(
		second.setup(aircraft, weapon_data, dive_data, solution),
		"a fresh controller can re-own the aircraft"
	)
	squadron.force_release_all_movement_owners(&"squadron_shutdown")
	_check(
		aircraft.is_movement_owned_by(AircraftMovementOwner.Type.FORMATION),
		"squadron lifecycle recovery frees every aircraft"
	)
	var snapshot := aircraft.get_movement_owner_debug_snapshot()
	_check(
		snapshot["movement_owner_name"] == "FORMATION" \
			and snapshot["movement_owner_reason"] == &"squadron_shutdown",
		"the debug snapshot exposes owner, reason and generation"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_MOVEMENT_OWNERSHIP_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
