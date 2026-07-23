extends SceneTree

var checks: int = 0
var failures: int = 0
var ballistic_impact_position: Variant


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var projectile_scene := load("res://scenes/weapon/projectile.tscn") as PackedScene
	var projectile := projectile_scene.instantiate() as Projectile
	root.add_child(projectile)
	projectile.gravity_scale = 0.0
	projectile.launch(Vector3(800.0, 20.0, 0.0), &"test")
	var trail := projectile.get_node_or_null("TrailParticles") as GPUParticles3D
	_check(trail != null, "projectile has a trail particle emitter")
	_check(trail != null and trail.emitting, "trail starts when projectile launches")
	_check(trail != null and trail.lifetime >= 0.8, "trail persists long enough for distant viewing")
	var trail_mesh := trail.draw_pass_1 as QuadMesh if trail != null else null
	_check(trail_mesh != null and trail_mesh.size.x >= 4.0, "trail width remains visible at RTS height")
	projectile.on_recycled_to_pool()
	_check(trail != null and not trail.emitting, "trail stops when projectile is recycled")

	var splash_scene := load("res://scenes/world/ocean/effects/water_splash_effect.tscn") as PackedScene
	var splash := splash_scene.instantiate() as WaterSplashEffect
	root.add_child(splash)
	splash.activate(Vector3.ZERO, 1.0, Vector3(0.0, -800.0, 0.0), Vector3.UP)
	_check(splash.scale.x >= 2.8, "standard water impact uses the enlarged visual scale")
	_check(splash.main_plume.amount >= 72, "water plume particle density is increased")
	_check(splash.mist.lifetime >= 3.0, "impact mist remains visible long enough")
	_check(splash.main_plume.visibility_aabb.size.y >= 100.0, "water plume has a distant visibility bound")
	var mist_mesh := splash.mist.draw_pass_1 as QuadMesh
	var mist_material := mist_mesh.material as StandardMaterial3D if mist_mesh != null else null
	_check(
		mist_material != null and mist_material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED,
		"water mist faces the RTS camera"
	)

	var ocean_scene := load("res://scenes/world/ocean.tscn") as PackedScene
	var ocean := ocean_scene.instantiate() as Node3D
	root.add_child(ocean)
	await process_frame
	var water_projectile := projectile_scene.instantiate() as Projectile
	root.add_child(water_projectile)
	water_projectile.global_position = Vector3(0.0, 18.0, 0.0)
	water_projectile.gravity_scale = 0.0
	water_projectile.launch(Vector3(0.0, -180.0, 0.0), &"test")
	for _frame in 12:
		await physics_frame
	var interaction := ocean.get_node("OceanInteraction") as OceanInteraction
	var water_state := interaction.get_pool_debug_state()
	_check(int(water_state.get("active_splashes", 0)) >= 1, "projectile water crossing activates a pooled splash")
	if not interaction.water_impact_registered.is_connected(_on_water_impact_registered):
		interaction.water_impact_registered.connect(_on_water_impact_registered)
	var ballistic_projectile := projectile_scene.instantiate() as Projectile
	root.add_child(ballistic_projectile)
	var ballistic_origin := Vector3(0.0, 18.0, 0.0)
	var ballistic_target := Vector3(5000.0, 0.0, 0.0)
	var muzzle_speed_mps := 760.0
	var gravity_multiplier := 4.25
	var effective_gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_multiplier
	var horizontal_distance := Vector2(
		ballistic_target.x - ballistic_origin.x,
		ballistic_target.z - ballistic_origin.z
	).length()
	var vertical_offset := ballistic_target.y - ballistic_origin.y
	var speed_squared := muzzle_speed_mps * muzzle_speed_mps
	var discriminant := speed_squared * speed_squared - effective_gravity * (
		effective_gravity * horizontal_distance * horizontal_distance + 2.0 * vertical_offset * speed_squared
	)
	var pitch_rad := atan(
		(speed_squared - sqrt(discriminant)) / (effective_gravity * horizontal_distance)
	)
	ballistic_projectile.global_position = ballistic_origin
	ballistic_projectile.gravity_scale = gravity_multiplier
	ballistic_projectile.launch(
		Vector3(cos(pitch_rad) * muzzle_speed_mps, sin(pitch_rad) * muzzle_speed_mps, 0.0),
		&"ballistic_test"
	)
	for _frame in 480:
		await physics_frame
		if ballistic_impact_position is Vector3:
			break
	_check(ballistic_impact_position is Vector3, "5 km ballistic projectile reaches the water")
	print("BALLISTIC_ACTUAL_5KM target=%s impact=%s" % [ballistic_target, ballistic_impact_position])
	_check(
		ballistic_impact_position is Vector3 \
			and Vector2(
				ballistic_impact_position.x - ballistic_target.x,
				ballistic_impact_position.z - ballistic_target.z
			).length() < 50.0,
		"actual enhanced-gravity projectile lands within 50 m of the 5 km target"
	)

	var combat_effect_pool := CombatEffectPool.new()
	root.add_child(combat_effect_pool)
	root.get_node("EventBus").projectile_ship_impact.emit(Vector3(10.0, 2.0, 5.0), 1.0, true)
	await process_frame
	_check(combat_effect_pool.get_active_ship_hit_count() == 1, "ship impact event activates an explosion")
	var active_explosion: ShipHitExplosionEffect
	for child in combat_effect_pool.get_children():
		if child is ShipHitExplosionEffect and child.active:
			active_explosion = child as ShipHitExplosionEffect
			break
	_check(active_explosion != null and active_explosion.visible, "ship hit explosion is visible")
	_check(active_explosion != null and active_explosion.flash_particles.emitting, "ship hit flash particles emit")
	_check(active_explosion != null and active_explosion.smoke_particles.emitting, "ship hit smoke particles emit")

	print("PROJECTILE_VISIBILITY checks=%d failures=%d" % [checks, failures])
	projectile.queue_free()
	splash.queue_free()
	ocean.queue_free()
	combat_effect_pool.queue_free()
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null and object_pool.has_method(&"clear_pool"):
		object_pool.call(&"clear_pool")
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("PROJECTILE_VISIBILITY failed: %s" % description)


func _on_water_impact_registered(impact) -> void:
	var projectile_reference: WeakRef = impact.get(&"projectile_reference") as WeakRef if impact != null else null
	var projectile: Variant = projectile_reference.get_ref() if projectile_reference != null else null
	if projectile is Projectile and projectile.team == &"ballistic_test":
		ballistic_impact_position = impact.get(&"world_position")
