extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const CARRIER_AI_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_ai_test.tres"
)

var _failures: Array[String] = []
var _spawned_count := 0
var _launched_count := 0
var _recovered_count := 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var event_bus := root.get_node_or_null("EventBus")
	if event_bus != null:
		event_bus.aircraft_spawned.connect(_on_aircraft_spawned)
		event_bus.squadron_launched.connect(_on_squadron_launched)
		event_bus.squadron_recovered.connect(_on_squadron_recovered)

	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = CARRIER_AI_STAGE
	root.add_child(battle)
	var carrier := _find_carrier(battle)
	_check(carrier != null, "test battle contains cv_seabastion")
	if carrier == null:
		await _finish(battle, event_bus)
		return
	carrier.carrier_air_group_ai.shutdown()
	carrier.carrier_air_group_ai.process_mode = \
		Node.PROCESS_MODE_DISABLED
	await process_frame
	await physics_frame

	_check(
		carrier.ship_data.carrier_air_group_data != null,
		"cv_seabastion owns CarrierAirGroupData"
	)
	_check(
		carrier.carrier_air_group != null \
			and carrier.carrier_air_group.process_mode \
				!= Node.PROCESS_MODE_DISABLED,
		"carrier air group is active only for the carrier"
	)
	var non_carrier_count := 0
	for ship_value in battle.get_battle_units():
		var ship := ship_value as ShipUnit
		if ship == null \
				or ship == carrier \
				or ship.ship_data == null \
				or ship.ship_data.carrier_air_group_data != null:
			continue
		non_carrier_count += 1
		_check(
			ship.carrier_air_group.process_mode == Node.PROCESS_MODE_DISABLED,
			"non-carrier air group component is disabled"
		)
	_check(non_carrier_count > 0, "test battle contains non-carrier ships")

	var test_data := _make_fast_test_air_group(
		carrier.ship_data.carrier_air_group_data
	)
	carrier.carrier_air_group.setup(carrier, test_data)
	carrier.carrier_air_group.process_mode = Node.PROCESS_MODE_INHERIT
	var ship_count_before := get_nodes_in_group(&"ships").size()
	var destination := carrier.global_position \
		+ -carrier.global_transform.basis.z.normalized() * 300.0
	destination.y = carrier.global_position.y + 80.0
	var squadron := carrier.launch_air_squadron(
		"basic_bomber_squadron",
		destination
	)
	_check(squadron != null, "carrier launches the configured squadron")
	if squadron == null:
		await _finish(battle, event_bus)
		return
	_check(
		squadron.aircraft_units.size() == 4,
		"squadron creates four aircraft"
	)
	var initial_aircraft_positions: Array[Vector3] = []
	for aircraft in squadron.aircraft_units:
		initial_aircraft_positions.append(aircraft.global_position)
	_check(
		not carrier.carrier_air_group.can_launch("basic_bomber_squadron"),
		"launch cooldown and template availability block an immediate relaunch"
	)
	await physics_frame
	_check(
		get_nodes_in_group(&"ships").size() == ship_count_before,
		"aircraft never join the ships group"
	)
	for aircraft in squadron.aircraft_units:
		_check(
			aircraft.is_in_group(&"aircraft"),
			"spawned unit joins the aircraft group"
		)
		_check(
			not aircraft.is_in_group(&"ships"),
			"spawned unit remains outside the ships group"
		)

	var reached_holding := await _wait_for_squadron_state(
		squadron,
		AircraftSquadron.State.HOLDING,
		360
	)
	_check(reached_holding, "squadron reaches its destination and holds")
	for index in range(squadron.aircraft_units.size()):
		var aircraft := squadron.aircraft_units[index]
		_check(
			aircraft.global_position.distance_to(
				initial_aircraft_positions[index]
			) > 100.0,
			"each aircraft follows the moving formation center"
		)
	carrier.global_position += Vector3(80.0, 0.0, 0.0)
	carrier.carrier_air_group.request_squadron_return(squadron)
	var recovered := await _wait_for_recovery(
		carrier.carrier_air_group,
		480
	)
	_check(recovered, "returning squadron tracks and recovers to the carrier")
	await process_frame
	await process_frame
	var aircraft_root := battle.get_node_or_null("Aircraft")
	var remaining_flight_nodes := 0
	if aircraft_root != null:
		for child in aircraft_root.get_children():
			if child is AircraftUnit or child is AircraftSquadron:
				remaining_flight_nodes += 1
	_check(
		aircraft_root != null and remaining_flight_nodes == 0,
		"recovered squadron and aircraft are removed"
	)
	carrier.carrier_air_group.call(&"_process", 1.0)
	_check(
		carrier.carrier_air_group.available_squadron_ids.has(
			"basic_bomber_squadron"
		),
		"recovered squadron becomes available after rearm cooldown"
	)
	_check(_spawned_count == 4, "EventBus reports four aircraft spawns")
	_check(_launched_count == 1, "EventBus reports one squadron launch")
	_check(_recovered_count == 1, "EventBus reports one squadron recovery")
	await _finish(battle, event_bus)


func _make_fast_test_air_group(
		source: CarrierAirGroupData
) -> CarrierAirGroupData:
	var result := source.duplicate(true) as CarrierAirGroupData
	result.launch_cooldown_sec = 0.05
	result.recovery_cooldown_sec = 0.05
	var template := result.squadron_templates[0]
	template.rearm_duration_sec = 0.05
	template.launch_interval_sec = 0.01
	var aircraft := template.aircraft_data.duplicate(true) as AircraftData
	aircraft.cruise_speed_mps = 260.0
	aircraft.maximum_speed_mps = 260.0
	aircraft.turn_rate_deg_sec = 180.0
	aircraft.operating_altitude_m = 80.0
	aircraft.arrival_distance_m = 30.0
	template.aircraft_data = aircraft
	return result


func _wait_for_squadron_state(
		squadron: AircraftSquadron,
		expected_state: AircraftSquadron.State,
		maximum_frames: int
) -> bool:
	for _frame in range(maximum_frames):
		if not is_instance_valid(squadron):
			return false
		if squadron.state == expected_state:
			return true
		await physics_frame
	return false


func _wait_for_recovery(
		air_group: CarrierAirGroup,
		maximum_frames: int
) -> bool:
	for _frame in range(maximum_frames):
		if air_group.get_active_squadrons().is_empty():
			return true
		await physics_frame
	return false


func _find_carrier(battle: BattleScene) -> ShipUnit:
	for ship_value in battle.get_battle_units():
		var ship := ship_value as ShipUnit
		if ship != null \
				and ship.ship_id == "cv_seabastion" \
				and ship.team == FactionRelations.ALLY:
			return ship
	return null


func _finish(battle: BattleScene, event_bus: Node) -> void:
	if event_bus != null:
		if event_bus.aircraft_spawned.is_connected(_on_aircraft_spawned):
			event_bus.aircraft_spawned.disconnect(_on_aircraft_spawned)
		if event_bus.squadron_launched.is_connected(_on_squadron_launched):
			event_bus.squadron_launched.disconnect(_on_squadron_launched)
		if event_bus.squadron_recovered.is_connected(_on_squadron_recovered):
			event_bus.squadron_recovered.disconnect(_on_squadron_recovered)
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER AIRCRAFT TEST: %s" % failure)
	print(
		"CARRIER_AIRCRAFT_SYSTEM_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _on_aircraft_spawned(_aircraft) -> void:
	_spawned_count += 1


func _on_squadron_launched(_squadron) -> void:
	_launched_count += 1


func _on_squadron_recovered(_squadron) -> void:
	_recovered_count += 1


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
