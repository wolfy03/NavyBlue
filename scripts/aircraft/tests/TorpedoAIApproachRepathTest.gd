extends SceneTree

# Integration test for the AI torpedo approach re-tracking (Phase 2).
#
# Reuses the proven launch path from TorpedoAttackAIPlannerIntegrationTest to get
# a live torpedo squadron with an active TorpedoAttackController in APPROACHING,
# then drives the mission controller directly (no scene ticking) to verify:
#   - a sub-threshold target move does NOT repath (revision unchanged);
#   - a large target move DOES repath (revision advances, impact follows the
#     target) while keeping the same tracked-attack identity (tracking_id).

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_ai_test.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await process_frame
	await physics_frame
	var carrier := _find_ai_carrier(battle)
	_check(carrier != null, "battle provides an AI carrier")
	if carrier == null:
		await _finish(battle)
		return

	var group := carrier.carrier_air_group
	var ai := carrier.carrier_air_group_ai
	ai.shutdown()
	group.setup(carrier, carrier.ship_data.carrier_air_group_data)
	var bomber_state := group.squadron_states.get(
		"basic_bomber_squadron"
	) as SquadronRuntimeState
	if bomber_state != null:
		bomber_state.available_aircraft = 0
		bomber_state.availability_state = \
			SquadronRuntimeState.AvailabilityState.REARMING
	ai.setup(carrier, group)
	ai.update_ai(10.0)
	var squadron := group.get_active_squadron_by_id(
		"basic_torpedo_squadron"
	)
	_check(squadron != null, "AI launches the torpedo bomber squadron")
	if squadron == null:
		await _finish(battle)
		return

	var controller := squadron.torpedo_attack_controller
	var mission := squadron.mission_controller
	_check(
		controller != null and controller.is_active(),
		"the torpedo attack controller is active after launch"
	)
	var target := mission.get_target_ship() as ShipUnit
	_check(target != null, "the mission has a ship target")
	if controller == null or not controller.is_active() or target == null:
		await _finish(battle)
		return

	# Freeze automatic ticking so we drive the mission deterministically.
	squadron.set_physics_process(false)
	squadron.set_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.set_physics_process(false)
		aircraft.set_process(false)
	target.set_physics_process(false)
	target.velocity = Vector3.ZERO

	var command := controller.get_command()
	_check(command != null, "the active attack exposes a command")
	if command == null:
		await _finish(battle)
		return
	_check(
		controller.can_update_attack_solution(),
		"the solution is open for re-aim during the approach"
	)
	var tracking_id := command.tracking_id
	# Exercise the re-tracking mechanic regardless of the AI mission's config.
	mission.mission_data.target_prediction_enabled = true

	# Establish a clean, velocity-frozen baseline: force one repath (threshold 0)
	# so the stored solution matches the now-stationary target and carries no
	# stale launch-time lead. A stationary target is not led, so the predicted
	# impact should equal the target position.
	var original_threshold := mission.mission_data.approach_repath_threshold_m
	mission.mission_data.approach_repath_threshold_m = 0.0
	mission.update_mission(0.6)
	mission.mission_data.approach_repath_threshold_m = original_threshold
	var synced := controller.get_command()
	_check(
		synced.predicted_impact_position.distance_to(target.global_position) \
			< 5.0,
		"the baseline solution matches the stationary target position"
	)
	_check(
		synced.tracking_id == tracking_id,
		"forcing a repath keeps the same tracked-attack identity"
	)
	var baseline_revision := synced.solution_revision

	# A large move (>> 150 m threshold) re-aims the run.
	target.global_position.x += 400.0
	mission.update_mission(0.6)
	var after_large := controller.get_command()
	_check(
		after_large.solution_revision > baseline_revision,
		"a large target move advances the solution revision"
	)
	_check(
		after_large.tracking_id == tracking_id,
		"the repath keeps the same tracked-attack identity"
	)
	_check(
		after_large.predicted_impact_position.distance_to(
			target.global_position
		) < 5.0,
		"the repathed solution follows the target's new position"
	)
	var large_revision := after_large.solution_revision

	# A sub-threshold move (< 150 m) is ignored.
	target.global_position.x += 40.0
	mission.update_mission(0.6)
	_check(
		controller.get_command().solution_revision == large_revision,
		"a sub-threshold target move does not repath the approach"
	)

	await _finish(battle)


func _find_ai_carrier(battle: BattleScene) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null \
				and ship.ship_id == "cv_seabastion" \
				and ship.team == FactionRelations.ALLY:
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	battle.shutdown()
	battle.queue_free()
	await process_frame
	await process_frame
	print(
		"TORPEDO_AI_APPROACH_REPATH_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO AI REPATH: %s" % label)
