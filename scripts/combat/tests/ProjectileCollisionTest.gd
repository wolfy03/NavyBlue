extends SceneTree

const EXPECTED_HP: float = 40.0
const EPSILON: float = 0.01

var ship_impact_event_count: int = 0


class DamageTarget:
	extends StaticBody3D

	var health: ShipHealth
	var last_penetration_result: int = -1
	var last_hit_info: HitInfo

	func configure() -> void:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 2.0, 4.0)
		shape.shape = box
		add_child(shape)

		var defense := ShipDefenseStats.new()
		defense.max_hp = 100.0
		defense.current_hp = 100.0
		defense.belt_armor = 50.0
		health = ShipHealth.new()
		health.debug_damage_log = false
		add_child(health)
		health.setup(defense)

	func get_defense_stats() -> ShipDefenseStats:
		return health.get_defense_stats()

	func apply_damage(damage: float, penetration_result: int, hit_info: HitInfo) -> float:
		last_penetration_result = penetration_result
		last_hit_info = hit_info
		return health.apply_damage(damage, penetration_result, hit_info)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var event_bus := root.get_node_or_null("EventBus")
	if event_bus != null and not event_bus.projectile_ship_impact.is_connected(_on_projectile_ship_impact):
		event_bus.projectile_ship_impact.connect(_on_projectile_ship_impact)
	var target := DamageTarget.new()
	root.add_child(target)
	target.global_position = Vector3(0.0, 5.0, 0.0)
	target.configure()

	var projectile_scene := load("res://scenes/weapon/projectile.tscn") as PackedScene
	var projectile := projectile_scene.instantiate() as Projectile
	root.add_child(projectile)
	projectile.global_position = Vector3(-8.0, 5.0, 0.0)
	projectile.gravity_scale = 0.0
	var ap := load("res://scripts/combat/default_ap_shell.tres").duplicate(true) as ShellStats
	ap.penetration = 120.0
	projectile.launch(Vector3.RIGHT * 120.0, &"test", ap)

	for _frame: int in 30:
		await physics_frame
		if target.last_hit_info != null:
			break

	var passed: bool = target.last_hit_info != null \
		and target.last_penetration_result == PenetrationResolver.Result.PENETRATED \
		and target.last_hit_info.armor_part == ArmorPart.Type.BELT \
		and absf(target.get_defense_stats().current_hp - EXPECTED_HP) <= EPSILON \
		and ship_impact_event_count == 1
	if passed:
		print("PROJECTILE_COLLISION_TEST PASS")
	else:
		push_error(
			"PROJECTILE_COLLISION_TEST FAIL hit=%s result=%d part=%d hp=%.2f position=%s local=%s direction=%s normal=%s" % [
				target.last_hit_info != null,
				target.last_penetration_result,
				target.last_hit_info.armor_part if target.last_hit_info != null else -1,
				target.get_defense_stats().current_hp,
				target.last_hit_info.hit_position if target.last_hit_info != null else Vector3.ZERO,
				target.to_local(target.last_hit_info.hit_position) if target.last_hit_info != null else Vector3.ZERO,
				target.last_hit_info.shell_direction if target.last_hit_info != null else Vector3.ZERO,
				target.last_hit_info.hit_normal if target.last_hit_info != null else Vector3.ZERO,
			]
		)
	if is_instance_valid(projectile):
		projectile.queue_free()
	target.queue_free()
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if passed else 1)


func _on_projectile_ship_impact(_position: Vector3, _strength: float, _penetrated: bool) -> void:
	ship_impact_event_count += 1
