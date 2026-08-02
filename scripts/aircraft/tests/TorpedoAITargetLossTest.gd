extends SceneTree

# Integration test for the AI torpedo target-loss policy (Phase 2, approach case).
#
# Reuses the launch path from TorpedoAttackAIPlannerIntegrationTest to get a live
# torpedo squadron whose TorpedoAttackController is APPROACHING, then destroys
# the target and drives one controller update to verify the run aborts before it
# commits: the controller leaves the active states, records target_lost, and no
# torpedoes are dropped (payload preserved). The mission then finalizes instead
# of hanging in the attack.

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

	squadron.set_physics_process(false)
	squadron.set_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
		aircraft.set_process(false)

	_check(
		controller.state == TorpedoAttackController.State.APPROACHING,
		"the run is still in the approach phase before target loss"
	)
	_check(
		controller.get_released_aircraft_count() == 0,
		"no torpedoes have been released yet"
	)

	# Destroy the target: is_alive() now returns false without freeing the node.
	target._is_sinking = true
	controller.update_attack(0.1)

	_check(
		not controller.is_active(),
		"losing the target during the approach ends the active run"
	)
	_check(
		controller.state == TorpedoAttackController.State.ABORTED,
		"the aborted run lands in the ABORTED state"
	)
	_check(
		controller.abort_reason == &"target_lost",
		"the abort reason records the target loss"
	)
	_check(
		controller.get_released_aircraft_count() == 0,
		"payload is preserved: no torpedoes were dropped on a dead target"
	)

	# The mission should finalize rather than stay stuck in the attack.
	mission.update_mission(0.1)
	_check(
		mission.state == AircraftMissionController.MissionState.FAILED \
			or mission.state \
				== AircraftMissionController.MissionState.RETURNING,
		"the mission finalizes after the aborted attack"
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
		"TORPEDO_AI_TARGET_LOSS_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO AI TARGET LOSS: %s" % label)
