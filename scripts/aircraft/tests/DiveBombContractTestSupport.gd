extends RefCounted
class_name DiveBombContractTestSupport
## Shared fixture for the per-aircraft dive-bomb behavior-contract tests.
## Spawns a real battle, launches a real bomber squadron with physics frozen,
## and provides helpers to place single aircraft into exact attack phases so
## each contract can be asserted deterministically without frame waits.

const BATTLE_SCENE_PATH := "res://scenes/world/battle_scene.tscn"
const STAGE_PATH := "res://resources/stages/tests/carrier_player_test.tres"


static func spawn_battle(tree_root: Node) -> BattleScene:
	var battle := (
		load(BATTLE_SCENE_PATH) as PackedScene
	).instantiate() as BattleScene
	battle.stage_override = load(STAGE_PATH) as StageData
	tree_root.add_child(battle)
	return battle


static func launch_frozen_squadron(battle: BattleScene) -> AircraftSquadron:
	var carrier := battle.player_ship as ShipUnit
	if carrier == null or carrier.carrier_air_group == null:
		return null
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	if squadron == null:
		return null
	squadron.set_physics_process(false)
	# Just-launched aircraft sit at deck height, below every release
	# altitude; hoist them to dive-entry height so current-state solves are
	# geometrically valid without simulating the whole climb.
	var entry_altitude := 350.0
	var dive_data := squadron.get_dive_bomber_combat_data()
	if dive_data != null:
		entry_altitude = maxf(dive_data.dive_entry_altitude_m, 100.0)
	squadron.formation_center.y = entry_altitude
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
		aircraft.global_position = squadron.formation_center \
			+ aircraft.formation_offset
		aircraft.global_position.y = entry_altitude
	return squadron


static func make_ship_request(
		target: ShipUnit,
		team: StringName
) -> DiveBombTargetRequest:
	var request := DiveBombTargetRequest.new()
	request.source = DiveBombTargetRequest.Source.PLAYER
	request.set_explicit_target(target)
	request.designated_world_position = target.global_position \
		if target != null and is_instance_valid(target) else Vector3.ZERO
	request.acquisition_radius_m = 250.0
	request.requesting_team = team
	request.allow_position_fallback = true
	return request


static func make_position_request(
		point: Vector3,
		team: StringName
) -> DiveBombTargetRequest:
	var request := DiveBombTargetRequest.new()
	request.source = DiveBombTargetRequest.Source.PLAYER
	request.designated_world_position = point
	request.acquisition_radius_m = 0.0
	request.requesting_team = team
	request.allow_position_fallback = true
	return request


## Coordinator set up in QUICK_ATTACK so controllers exist immediately after
## the first update (no approach transit).
static func begin_quick_attack(
		squadron: AircraftSquadron,
		request: DiveBombTargetRequest
) -> SquadronDiveBombCoordinator:
	var coordinator := SquadronDiveBombCoordinator.new()
	if not coordinator.setup(
		squadron,
		request,
		DiveBombAttackMode.Type.QUICK_ATTACK,
		1
	):
		return null
	coordinator.update(0.0)
	return coordinator


## Teleports one aircraft into an open release window of its own solution:
## on the locked attack line at the automatic release altitude, aligned and
## flying the locked dive direction, past the minimum dive time.
static func place_in_release_window(
		controller: AircraftDiveBombController
) -> void:
	var aircraft := controller.attack_state.get_aircraft()
	var solution := controller.attack_state.solution
	var dive_data := controller.dive_data
	var aim := solution.final_aim_impact_position
	var direction := controller.attack_state.locked_attack_direction
	var altitude := clampf(
		dive_data.automatic_release_altitude_m,
		dive_data.minimum_release_altitude_m,
		dive_data.maximum_release_altitude_m
	)
	var position := solution.release_position
	position.y = aim.y + altitude
	aircraft.global_position = position
	aircraft.global_transform.basis = Basis.looking_at(
		controller.attack_state.locked_dive_direction,
		Vector3.UP
	)
	aircraft.velocity = controller.attack_state.locked_dive_direction \
		* dive_data.dive_speed_mps
	controller.attack_state.state = DiveBombAircraftAttackState.State.DIVING
	controller.attack_state.dive_elapsed_sec = maxf(
		dive_data.minimum_dive_time_before_release_sec + 0.1,
		0.2
	)
	# The window checks track vs locked direction; keep them identical.
	controller.attack_state.locked_attack_direction = direction


static func finish(
		tree: SceneTree,
		battle: BattleScene,
		test_name: String,
		failures: Array
) -> void:
	if battle != null and is_instance_valid(battle):
		battle.queue_free()
	for failure in failures:
		push_error("%s: %s" % [test_name, failure])
	print(
		"%s %s" % [test_name, "PASS" if failures.is_empty() else "FAIL"]
	)
	tree.quit(0 if failures.is_empty() else 1)
