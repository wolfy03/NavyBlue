extends SceneTree
## Release cancellation contract (§6): cancelling an in-flight attack keeps
## unspent ammunition, keeps already-spawned projectiles, returns movement
## ownership, and a late release outcome from the cancelled generation never
## resurrects the terminated controller state.

var _failures: Array[String] = []
var _spawned_projectiles := 0


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
	for aircraft in squadron.aircraft_units:
		aircraft.weapon_controller.weapon_released.connect(
			func(_aircraft: AircraftUnit, projectile: Node) -> void:
				if projectile != null:
					_spawned_projectiles += 1
		)
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
	_check(controllers.size() >= 2, "at least two aircraft controllers")
	if controllers.size() < 2:
		await _finish(battle)
		return

	# --- One aircraft has already dropped: its projectile must survive.
	var released_controller := controllers[0]
	var released_aircraft := released_controller.attack_state.get_aircraft()
	DiveBombContractTestSupport.place_in_release_window(released_controller)
	released_controller.update(1.0 / 60.0)
	_check(
		released_controller.attack_state.released,
		"precondition: the first aircraft has released"
	)
	_check(_spawned_projectiles == 1, "precondition: one live projectile")

	# --- Cancel mid-dive for the second aircraft.
	var diving_controller := controllers[1]
	var diving_aircraft := diving_controller.attack_state.get_aircraft()
	DiveBombContractTestSupport.place_in_release_window(diving_controller)
	var ammunition_before := \
		diving_aircraft.weapon_controller.get_remaining_ammunition()
	var generation_before: int = diving_controller.attack_generation
	coordinator.cancel(&"player_override")
	_check(
		coordinator.state == SquadronDiveBombCoordinator.State.CANCELLED,
		"coordinator reports CANCELLED"
	)
	_check(
		diving_controller.attack_state.release_block_reason \
			== DiveBombReleaseBlockReason.Type.CANCELLED,
		"the diving aircraft records the cancellation"
	)
	_check(
		diving_aircraft.weapon_controller.get_remaining_ammunition() \
			== ammunition_before,
		"cancellation keeps the unspent bomb aboard"
	)
	_check(
		diving_controller.attack_generation > generation_before,
		"cancellation advances the attack generation"
	)
	_check(
		diving_aircraft.is_movement_owned_by(
			AircraftMovementOwner.Type.FORMATION
		),
		"cancellation returns movement ownership"
	)
	_check(
		released_aircraft.is_movement_owned_by(
			AircraftMovementOwner.Type.FORMATION
		),
		"the released aircraft is returned to formation too"
	)

	# --- A late/stale update cannot resurrect the cancelled attack.
	var state_after_cancel := diving_controller.attack_state.state
	for _frame in 10:
		diving_controller.update(1.0 / 60.0)
	_check(
		diving_controller.attack_state.state == state_after_cancel,
		"late updates never resurrect a cancelled controller"
	)
	_check(
		_spawned_projectiles == 1,
		"no extra projectile spawns after cancellation"
	)
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_INDIVIDUAL_RELEASE_CANCELLATION_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
