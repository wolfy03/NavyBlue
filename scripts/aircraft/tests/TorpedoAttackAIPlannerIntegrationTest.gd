extends SceneTree

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
	if carrier != null:
		var group := carrier.carrier_air_group
		var ai := carrier.carrier_air_group_ai
		ai.shutdown()
		group.setup(carrier, carrier.ship_data.carrier_air_group_data)
		var bomber_state := group.squadron_states.get(
			"basic_bomber_squadron"
		) as SquadronRuntimeState
		bomber_state.available_aircraft = 0
		bomber_state.availability_state = \
			SquadronRuntimeState.AvailabilityState.REARMING
		ai.setup(carrier, group)
		ai.update_ai(10.0)
		var torpedo_squadron := group.get_active_squadron_by_id(
			"basic_torpedo_squadron"
		)
		_check(
			torpedo_squadron != null,
			"AI launches the available torpedo bomber squadron"
		)
		_check(
			torpedo_squadron != null \
				and torpedo_squadron.mission_controller.mission_data != null \
				and torpedo_squadron.mission_controller.mission_data \
					.mission_type \
					== AirMissionData.MissionType.TORPEDO_ATTACK,
			"AI assigns typed TORPEDO_ATTACK mission data"
		)
		_check(
			torpedo_squadron != null \
				and torpedo_squadron.torpedo_attack_controller.is_active(),
			"AI and player share the TorpedoAttackController"
		)
	battle.shutdown()
	battle.queue_free()
	await process_frame
	await process_frame
	print(
		"TORPEDO_ATTACK_AI_PLANNER_INTEGRATION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _find_ai_carrier(battle: BattleScene) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null \
				and ship.ship_id == "cv_seabastion" \
				and ship.team == FactionRelations.ALLY:
			return ship
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO AI: %s" % label)
