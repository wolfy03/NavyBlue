extends SceneTree

const DEFAULT_FACTION_PALETTE: FactionPalette = preload(
	"res://resources/factions/default_faction_palette.tres"
)

var _failures: Array[String] = []
var _destroyed_count := 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var effects := CombatEffectController.new()
	arena.add_child(effects)
	await process_frame
	var battle_services := BattleServices.new()
	battle_services.setup(
		root.get_node_or_null("EventBus"),
		root.get_node_or_null("ObjectPool"),
		root.get_node_or_null("RunManager"),
		root.get_node_or_null("GameManager"),
		DEFAULT_FACTION_PALETTE
	)
	effects.setup(battle_services.events)
	var fighter_data := FighterTestSupport.FIGHTER_DATA.duplicate(
		true
	) as AircraftData
	fighter_data.fighter_combat_data.base_accuracy = 1.0
	fighter_data.fighter_combat_data.minimum_accuracy = 1.0
	fighter_data.fighter_combat_data.maximum_accuracy = 1.0
	fighter_data.fighter_combat_data.target_evasion_weight = 0.0
	fighter_data.fighter_combat_data.lock_time_sec = 0.2
	fighter_data.weapon_data.gun_data.mechanical_accuracy = 1.0
	var attacker := FighterTestSupport.spawn_aircraft(
		arena,
		fighter_data,
		FactionRelations.PLAYER,
		Vector3.ZERO,
		Vector3.FORWARD,
		battle_services
	)
	var target := FighterTestSupport.spawn_aircraft(
		arena,
		FighterTestSupport.BOMBER_DATA,
		FactionRelations.ENEMY,
		Vector3(0.0, 0.0, -300.0),
		Vector3.FORWARD,
		battle_services
	)
	target.destroyed.connect(_on_target_destroyed)
	var controller := attacker.fighter_combat_controller
	controller.set_target(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	var initial_ammo := attacker.weapon_controller.get_remaining_ammunition()
	var locking := controller.update_combat(0.1, rng)
	_check(
		locking.rounds_fired == 0 \
			and attacker.weapon_controller.get_remaining_ammunition() \
				== initial_ammo,
		"gun does not fire before lock time"
	)
	var fired := controller.update_combat(0.1, rng)
	_check(
		fired.rounds_fired == 8 \
			and fired.hit_count == 8 \
			and fired.total_damage == 40.0,
		"locked controller resolves one full burst"
	)
	_check(_destroyed_count == 1, "AircraftHealth emits destruction once")
	_check(
		int(effects.get_debug_state().get(
			"active_fighter_tracers",
			0
		)) == 1,
		"gun burst activates one pooled tracer effect"
	)

	var second_target := FighterTestSupport.spawn_aircraft(
		arena,
		FighterTestSupport.BOMBER_DATA,
		FactionRelations.ENEMY,
		Vector3(300.0, 0.0, 0.0),
		Vector3.FORWARD,
		battle_services
	)
	controller.reset_for_sortie()
	attacker.weapon_controller.reset_for_sortie()
	controller.set_target(second_target)
	controller.update_combat(0.2, rng)
	_check(
		attacker.weapon_controller.get_remaining_ammunition() \
			== fighter_data.weapon_data.ammunition_per_sortie,
		"leaving firing cone resets lock and prevents fire"
	)
	effects.shutdown()
	effects.clear_pools()
	battle_services.shutdown()
	arena.queue_free()
	await process_frame
	await process_frame
	_finish()


func _on_target_destroyed(_aircraft: AircraftUnit) -> void:
	_destroyed_count += 1


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("FIGHTER COMBAT CONTROLLER TEST: %s" % failure)
	print(
		"FIGHTER_COMBAT_CONTROLLER_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)
