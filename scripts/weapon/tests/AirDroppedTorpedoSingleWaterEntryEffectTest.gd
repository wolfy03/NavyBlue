extends SceneTree

# Verifies §19: an air-dropped torpedo raises exactly one water-entry splash,
# routed through the standard projectile-impact effect path so
# CombatEffectPresenter renders it, and never repeats it once running.

const TORPEDO_SCENE := preload(
	"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
)

var _failures := PackedStringArray()
var _water_impacts := 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleTestServices.create(self)
	services.events.projectile_impact.connect(_on_projectile_impact)
	var projectile_root := Node3D.new()
	projectile_root.name = "Projectiles"
	root.add_child(projectile_root)
	var torpedo := TORPEDO_SCENE.instantiate() as TorpedoProjectile
	projectile_root.add_child(torpedo)
	var data := load(
		"res://resources/projectiles/aircraft_torpedo.tres"
	) as TorpedoProjectileData
	var context := ProjectileLaunchContext.new()
	context.source_team = FactionRelations.PLAYER
	context.source_weapon_id = &"water_entry_test"
	context.initial_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 25.0, 0.0)
	)
	context.initial_velocity = Vector3(0.0, -5.0, -65.0)
	context.torpedo_launch_mode = TorpedoLaunchMode.Type.AIR_DROPPED
	context.intended_launch_direction = Vector3.FORWARD
	_check(torpedo.configure(data, services), "air torpedo configures")
	_check(torpedo.launch(context), "air torpedo launches airborne")

	# Drop below the sea surface to trigger the single water entry.
	torpedo.global_position = Vector3(0.0, -0.1, 10.0)
	torpedo.call(&"_physics_process", 0.1)
	_check(
		torpedo.launch_phase == TorpedoProjectile.LaunchPhase.ARMING,
		"torpedo enters the water and begins arming"
	)
	_check(_water_impacts == 1, "exactly one water-entry effect is emitted")

	# Further running steps must not emit another water entry.
	torpedo.call(&"_physics_process", 0.1)
	_check(_water_impacts == 1, "no duplicate water-entry effect while running")

	if services.events.projectile_impact.is_connected(_on_projectile_impact):
		services.events.projectile_impact.disconnect(_on_projectile_impact)
	torpedo.queue_free()
	projectile_root.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null and object_pool.has_method(&"clear_pool"):
		object_pool.call(&"clear_pool")
	await process_frame
	print(
		"AIR_DROPPED_TORPEDO_SINGLE_WATER_ENTRY_EFFECT_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _on_projectile_impact(result: ProjectileImpactResult) -> void:
	if result != null \
			and result.surface_type == ProjectileImpactResult.SurfaceType.WATER:
		_water_impacts += 1


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO WATER ENTRY: %s" % label)
