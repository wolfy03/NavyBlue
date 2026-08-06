extends SceneTree
## Clamped destination contract (§21-22): when the planner's approach request
## lies outside the combat radius, the coordinator's authoritative approach
## position is the destination movement ACTUALLY assigned (clamped), and the
## clamp offset is visible in the debug snapshot.

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
	var carrier := battle.player_ship as ShipUnit
	var combat_radius: float = \
		squadron.squadron_data.aircraft_data.combat_radius_m
	# A designation far beyond the combat radius: the movement system must
	# clamp whatever approach point the planner computes for it.
	var designation: Vector3 = carrier.global_position \
		+ Vector3(0.0, 0.0, combat_radius * 2.0)
	designation.y = 0.0
	var coordinator := SquadronDiveBombCoordinator.new()
	_check(
		coordinator.setup(
			squadron,
			DiveBombContractTestSupport.make_position_request(
				designation,
				squadron.get_team()
			),
			DiveBombAttackMode.Type.NORMAL_APPROACH,
			1
		),
		"normal approach coordinator starts"
	)
	coordinator.update(0.0)
	_check(
		coordinator.state == SquadronDiveBombCoordinator.State.APPROACHING,
		"the coordinator is approaching"
	)
	_check(
		coordinator._approach_position == squadron.destination,
		"the authoritative approach position is the assigned destination"
	)
	var carrier_offset: Vector3 = \
		coordinator._approach_position - carrier.global_position
	carrier_offset.y = 0.0
	_check(
		carrier_offset.length() <= combat_radius + 1.0,
		"the assigned approach destination respects the combat radius"
	)
	var snapshot := coordinator.get_debug_snapshot()
	_check(
		float(snapshot["approach_clamp_offset_m"]) > 1.0,
		"the clamp offset between requested and assigned is reported"
	)
	coordinator.cancel(&"test_finished")
	await _finish(battle)


func _finish(battle: BattleScene) -> void:
	await process_frame
	DiveBombContractTestSupport.finish(
		self,
		battle,
		"DIVE_BOMB_APPROACH_DESTINATION_CLAMP_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
