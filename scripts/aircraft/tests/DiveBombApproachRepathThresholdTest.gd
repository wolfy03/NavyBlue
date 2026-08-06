extends SceneTree
## Approach repath contract (§19-20, §22): sub-threshold movement of the
## approach point keeps the active destination command (same serial); a
## change beyond the authored threshold issues a new destination with a new
## serial; a continuously moving target keeps being tracked.

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
	target.velocity = Vector3.ZERO
	target.global_position = squadron.formation_center \
		+ Vector3(0.0, 0.0, 2500.0)
	target.global_position.y = 0.0
	var dive_data := squadron.get_dive_bomber_combat_data()
	var coordinator := SquadronDiveBombCoordinator.new()
	_check(
		coordinator.setup(
			squadron,
			DiveBombContractTestSupport.make_ship_request(
				target,
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
	var first_serial: int = coordinator._approach_destination_serial
	_check(first_serial >= 0, "the first approach issues a destination")
	var repath_count_before: int = coordinator.approach_repath_count

	# --- Sub-threshold target movement keeps the serial.
	target.global_position += Vector3(
		maxf(dive_data.approach_repath_threshold_m * 0.3, 1.0),
		0.0,
		0.0
	)
	coordinator.update(dive_data.approach_repath_interval_sec + 0.05)
	_check(
		coordinator._approach_destination_serial == first_serial,
		"sub-threshold movement keeps the destination serial"
	)

	# --- Beyond-threshold movement issues a new serial.
	target.global_position += Vector3(
		dive_data.approach_repath_threshold_m * 4.0,
		0.0,
		0.0
	)
	coordinator.update(dive_data.approach_repath_interval_sec + 0.05)
	var second_serial: int = coordinator._approach_destination_serial
	_check(
		second_serial != first_serial,
		"beyond-threshold movement issues a new destination serial"
	)
	_check(
		coordinator.approach_repath_count > repath_count_before,
		"the repath diagnostic counts the new command"
	)

	# --- A continuously moving target keeps being tracked.
	var assigned_before: Vector3 = coordinator._approach_position
	for _step in 8:
		target.global_position += Vector3(120.0, 0.0, 0.0)
		coordinator.update(dive_data.approach_repath_interval_sec + 0.05)
	var assigned_after: Vector3 = coordinator._approach_position
	_check(
		assigned_after.distance_to(assigned_before) > 100.0,
		"a moving target drags the assigned approach destination"
	)
	_check(
		coordinator._approach_position == squadron.destination,
		"the coordinator keeps the destination movement actually assigned"
	)
	var snapshot := coordinator.get_debug_snapshot()
	_check(
		snapshot.has("approach_requested_position") \
			and snapshot.has("approach_assigned_position") \
			and snapshot.has("approach_clamp_offset_m") \
			and snapshot.has("approach_repath_count"),
		"the snapshot exposes requested/assigned/clamp/repath diagnostics"
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
		"DIVE_BOMB_APPROACH_REPATH_THRESHOLD_TEST",
		_failures
	)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
