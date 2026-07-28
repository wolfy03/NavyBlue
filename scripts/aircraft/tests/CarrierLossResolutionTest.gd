extends SceneTree

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const CARRIER_AI_STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_ai_test.tres"
)
const SQUADRON_ID := "basic_bomber_squadron"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = CARRIER_AI_STAGE
	root.add_child(battle)
	var carrier := _find_carrier(battle)
	_check(carrier != null, "carrier exists")
	if carrier == null:
		await _finish(battle)
		return
	carrier.carrier_air_group_ai.shutdown()
	await process_frame
	var group := carrier.carrier_air_group
	var squadron := group.launch_squadron(
		SQUADRON_ID,
		carrier.global_position + Vector3(0.0, 100.0, -500.0)
	)
	_check(squadron != null, "active squadron launches before loss")
	var released_projectile: Node
	if squadron != null and not squadron.aircraft_units.is_empty():
		var aircraft := squadron.aircraft_units[0]
		aircraft.activate()
		var projectiles := battle.projectiles_root
		var before := projectiles.get_child_count()
		aircraft.weapon_controller.release(
			carrier.global_position + Vector3(0.0, 0.0, -300.0)
		)
		if projectiles.get_child_count() > before:
			released_projectile = projectiles.get_child(
				projectiles.get_child_count() - 1
			)
	group.resolve_carrier_loss()
	_check(
		released_projectile != null \
			and is_instance_valid(released_projectile),
		"already released projectile survives carrier loss"
	)
	if squadron != null:
		for aircraft in squadron.get_alive_aircraft():
			_check(
				not aircraft.weapon_controller.can_release(),
				"unreleased aircraft weapons are disabled"
			)
	for _frame in 30:
		await physics_frame
	var state := group.get_squadron_state(SQUADRON_ID)
	_check(
		state != null \
			and state.active_aircraft == 0 \
			and state.lost_aircraft == state.total_aircraft,
		"carrier loss settles all squadron aircraft once"
	)
	_check(
		group.get_active_squadron_count() == 0,
		"carrier loss safely removes active squadrons"
	)
	carrier.health.died.emit()
	_check(
		not carrier.carrier_air_group_ai.is_physics_processing(),
		"carrier death stops air group AI"
	)
	await _finish(battle)


func _find_carrier(battle: BattleScene) -> ShipUnit:
	for value in battle.allies:
		var ship := value as ShipUnit
		if ship != null and ship.ship_id == "cv_seabastion":
			return ship
	return null


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("CARRIER LOSS RESOLUTION TEST: %s" % failure)
	print(
		"CARRIER_LOSS_RESOLUTION_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
