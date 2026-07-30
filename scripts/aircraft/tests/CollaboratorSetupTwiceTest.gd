extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await process_frame
	var carrier := battle.player_ship
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null, "manual squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	var coordinator := squadron.payload_release_coordinator
	var settings := squadron.squadron_data.payload_release_settings
	coordinator.setup(squadron, settings)
	_register_alive_aircraft(coordinator, squadron)
	coordinator.setup(squadron, settings)
	_register_alive_aircraft(coordinator, squadron)
	for aircraft in squadron.get_alive_aircraft():
		var weapon := aircraft.weapon_controller
		_check(
			weapon.payload_release_completed.get_connections().size() == 1,
			"setup twice keeps one completed callback"
		)
		_check(
			weapon.payload_release_failed.get_connections().size() == 1,
			"setup twice keeps one failed callback"
		)
		_check(
			weapon.payload_release_cancelled.get_connections().size() == 1,
			"setup twice keeps one cancelled callback"
		)
	coordinator.shutdown()
	coordinator.shutdown()
	for aircraft in squadron.get_alive_aircraft():
		var weapon := aircraft.weapon_controller
		_check(
			weapon.payload_release_completed.get_connections().is_empty()
				and weapon.payload_release_failed.get_connections().is_empty()
				and weapon.payload_release_cancelled.get_connections().is_empty(),
			"shutdown twice disconnects weapon callbacks"
		)
	coordinator.setup(squadron, settings)
	_register_alive_aircraft(coordinator, squadron)
	_check(
		coordinator.owner_squadron == squadron,
		"collaborator can be configured after shutdown"
	)
	await _finish(battle)


func _register_alive_aircraft(
		coordinator: AircraftPayloadReleaseCoordinator,
		squadron: AircraftSquadron
) -> void:
	for aircraft in squadron.get_alive_aircraft():
		coordinator.register_aircraft(aircraft)


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	await physics_frame
	for failure in _failures:
		push_error("COLLABORATOR LIFECYCLE: %s" % failure)
	print(
		"COLLABORATOR_SETUP_TWICE_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
