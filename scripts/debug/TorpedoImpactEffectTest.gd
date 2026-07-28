extends Node3D

var _failures: Array[String] = []
var _torpedo_hit_count := 0
var _water_impact_count := 0
var _last_result: DamageResult
var _last_water_position := Vector3.ZERO


func _ready() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var packed := load(
		"res://scenes/world/battle_scene.tscn"
	) as PackedScene
	var battle := packed.instantiate() as BattleScene if packed != null else null
	_check(battle != null, "battle scene instantiates")
	if battle == null:
		_finish()
		return
	add_child(battle)
	await get_tree().process_frame
	await get_tree().physics_frame
	for ship_value: Variant in battle.get_battle_units():
		if ship_value != null and is_instance_valid(ship_value):
			var ship := ship_value as Node
			ship.set_process(false)
			ship.set_physics_process(false)

	var controller := battle.get_node_or_null(
		"CombatEffectController"
	) as CombatEffectController
	var interaction := get_tree().get_first_node_in_group(
		&"ocean_interaction"
	)
	var player := battle.player_ship as ShipUnit
	var enemy := battle.enemies.back() as ShipUnit \
		if not battle.enemies.is_empty() else null
	_check(controller != null, "battle contains CombatEffectController")
	_check(interaction != null, "battle contains OceanInteraction")
	_check(player != null and enemy != null, "battle provides torpedo test ships")
	if controller == null or interaction == null \
			or player == null or enemy == null:
		battle.queue_free()
		_finish()
		return

	var event_bus := get_node_or_null("/root/EventBus")
	if event_bus != null:
		event_bus.torpedo_hit.connect(_on_torpedo_hit)
		event_bus.projectile_water_impact.connect(_on_water_impact)
	var effect_before := controller.get_debug_state()
	var splash_before := interaction.call(&"get_pool_debug_state") as Dictionary
	var weapon := WeaponDatabase.new().get_weapon(
		"destroyer_torpedo_launcher"
	)
	var torpedo_data := weapon.projectile_data.duplicate(
		true
	) as TorpedoProjectileData
	torpedo_data.flooding_chance = 0.0
	var projectiles_root := battle.get_node("Projectiles")
	var object_pool := get_node_or_null("/root/ObjectPool")
	var torpedo := object_pool.spawn(
		weapon.projectile_scene,
		projectiles_root
	) as TorpedoProjectile
	_check(torpedo != null, "actual torpedo spawns through ObjectPool")
	if torpedo == null:
		battle.queue_free()
		_finish()
		return
	torpedo.setup_projectile_data(torpedo_data)
	var hit_position := enemy.global_position
	hit_position.y = -torpedo_data.running_depth_m
	var context := ProjectileLaunchContext.new()
	context.source_ship = player
	context.source_team = player.team
	context.source_weapon_id = StringName(weapon.id)
	context.initial_transform = Transform3D(
		Basis.IDENTITY,
		hit_position
	)
	context.aim_point = enemy.global_position
	var hp_before := enemy.get_current_hp()
	torpedo.launch_with_context(context)
	torpedo.call(&"_resolve_ship_hit", enemy, hit_position)
	var hp_after := enemy.get_current_hp()
	var effect_after := controller.get_debug_state()
	var splash_after := interaction.call(&"get_pool_debug_state") as Dictionary

	_check(_torpedo_hit_count == 1, "torpedo_hit EventBus signal emits once")
	_check(
		_last_result != null \
			and _last_result.hit_outcome == HitOutcome.Type.TORPEDO_HIT,
		"actual torpedo resolves as TORPEDO_HIT"
	)
	_check(
		int(effect_after.get("active_torpedo_impacts", 0))
			== int(effect_before.get("active_torpedo_impacts", 0)) + 1,
		"torpedo hit activates one underwater impact effect"
	)
	_check(
		int(splash_after.get("active_splashes", 0))
			== int(splash_before.get("active_splashes", 0)) + 1,
		"torpedo hit activates one surface splash"
	)
	_check(
		_water_impact_count == 1,
		"torpedo hit emits one water impact"
	)
	_check(
		CombatGeometryXZ.distance_xz(
			_last_water_position,
			hit_position
		) <= 0.01,
		"torpedo splash uses the hit position XZ"
	)
	_check(
		is_equal_approx(
			_last_water_position.y,
			WaterIntersection.get_water_height(
				torpedo,
				hit_position,
				torpedo.water_height_m
			)
		),
		"torpedo splash uses the water surface height"
	)
	_check(
		_last_result != null \
			and is_equal_approx(
				hp_before - hp_after,
				_last_result.final_damage
			),
		"torpedo effect service applies no additional damage"
	)

	await get_tree().process_frame
	if event_bus != null:
		if event_bus.torpedo_hit.is_connected(_on_torpedo_hit):
			event_bus.torpedo_hit.disconnect(_on_torpedo_hit)
		if event_bus.projectile_water_impact.is_connected(_on_water_impact):
			event_bus.projectile_water_impact.disconnect(_on_water_impact)
	if object_pool != null:
		object_pool.clear_pool()
	battle.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	_finish()


func _on_torpedo_hit(_torpedo, _target_ship, result) -> void:
	_torpedo_hit_count += 1
	_last_result = result as DamageResult


func _on_water_impact(position: Vector3, _strength: float) -> void:
	_water_impact_count += 1
	_last_water_position = position


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("TORPEDO IMPACT EFFECT TEST: %s" % failure)
	if _failures.is_empty():
		print("TORPEDO_IMPACT_EFFECT_TEST PASS")
	get_tree().quit(0 if _failures.is_empty() else 1)
