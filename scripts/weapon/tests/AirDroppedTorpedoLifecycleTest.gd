extends SceneTree

const TORPEDO_SCENE := preload(
	"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleTestServices.create(self)
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
	context.source_weapon_id = &"air_drop_test"
	context.initial_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 25.0, 0.0)
	)
	context.initial_velocity = Vector3(0.0, -5.0, -65.0)
	context.torpedo_launch_mode = TorpedoLaunchMode.Type.AIR_DROPPED
	context.intended_launch_direction = Vector3.FORWARD
	_check(torpedo.configure(data, services), "air torpedo configures")
	_check(torpedo.launch(context), "air torpedo launches")
	_check(
		torpedo.launch_phase == TorpedoProjectile.LaunchPhase.AIRBORNE,
		"air launch starts airborne"
	)
	_check(torpedo.gravity_scale > 0.0, "airborne torpedo uses gravity")
	_check(
		torpedo.collision_layer == 0 and torpedo.collision_mask == 0,
		"airborne torpedo cannot deal collision damage"
	)
	torpedo.global_position = Vector3(0.0, -0.1, 10.0)
	torpedo.call(&"_physics_process", 0.1)
	_check(
		torpedo.launch_phase == TorpedoProjectile.LaunchPhase.ARMING,
		"water entry joins existing arming phase"
	)
	_check(
		is_equal_approx(torpedo.gravity_scale, 0.0),
		"water-running torpedo disables gravity"
	)
	var forward := -torpedo.global_basis.z
	forward.y = 0.0
	_check(
		forward.normalized().is_equal_approx(Vector3.FORWARD),
		"water run preserves commanded attack direction"
	)
	torpedo.reset_for_pool()
	_check(
		torpedo.launch_mode == TorpedoLaunchMode.Type.SURFACE \
			and torpedo.intended_launch_direction == Vector3.ZERO,
		"pool reset clears air-drop state"
	)
	torpedo.queue_free()
	projectile_root.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null and object_pool.has_method(&"clear_pool"):
		object_pool.call(&"clear_pool")
	await process_frame
	print(
		"AIR_DROPPED_TORPEDO_LIFECYCLE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("AIR TORPEDO: %s" % label)
