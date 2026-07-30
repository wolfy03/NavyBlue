extends Node3D
class_name RicochetProjectileVisual

@export var fallback_lifetime_seconds := 6.0
@export var lifetime_margin_seconds := 0.75
@export var emergency_maximum_lifetime_seconds := 30.0
@export var gravity_scale := 0.45
@export_range(0.0, 1.0, 0.01) var retained_speed_ratio := 0.3
@export_range(0.0, 2.0, 0.05) var upward_bias := 0.12
@export_range(0.0, 0.5, 0.01) var direction_randomness := 0.05
@export_range(0.0, 0.5, 0.01) var minimum_upward_component := 0.08
@export var maximum_upward_speed_mps := 80.0
@export var surface_offset_m := 0.2
@export var forward_offset_m := 0.1
@export_range(0.0, 2.0, 0.05) var splash_strength_multiplier := 0.45
@export var trail_lifetime_seconds := 0.65
@export var trail_color := Color(1.0, 0.54, 0.18, 0.82)

var active_lifetime_seconds := 0.0
var velocity := Vector3.ZERO
var age_seconds := 0.0
var water_height_m := 0.0
var active := false
var water_impact_processed := false
var base_splash_strength := 1.0
var ocean_manager_ref: WeakRef
var pool_service: ProjectilePoolService
var events: BattleEventPublisher
var _despawn_requested := false

@onready var trail_particles: GPUParticles3D = get_node_or_null(
	"TrailParticles"
) as GPUParticles3D


func _ready() -> void:
	_configure_trail()
	on_recycled_to_pool()


func launch(
		hit_position: Vector3,
		incoming_velocity: Vector3,
		hit_normal: Vector3,
		sea_level_m: float,
		next_base_splash_strength: float = 1.0,
		ocean_manager: Node = null,
		next_pool_service: ProjectilePoolService = null,
		next_events: BattleEventPublisher = null
) -> void:
	pool_service = next_pool_service
	events = next_events
	water_height_m = sea_level_m
	base_splash_strength = maxf(next_base_splash_strength, 0.0)
	_cache_ocean_manager(ocean_manager)
	var incoming_direction := incoming_velocity.normalized()
	if incoming_direction.length_squared() <= 0.000001:
		incoming_direction = Vector3.FORWARD
	var normal := hit_normal.normalized()
	if normal.length_squared() <= 0.000001:
		normal = Vector3.UP
	var reflected_direction := incoming_direction.bounce(normal)
	reflected_direction = (
		reflected_direction
		+ Vector3.UP * upward_bias
		+ Vector3(
			randf_range(-direction_randomness, direction_randomness),
			randf_range(0.0, direction_randomness),
			randf_range(-direction_randomness, direction_randomness)
		)
	)
	reflected_direction.y = maxf(
		reflected_direction.y,
		minimum_upward_component
	)
	reflected_direction = reflected_direction.normalized()
	global_position = hit_position \
		+ normal * maxf(surface_offset_m, 0.0) \
		+ reflected_direction * maxf(forward_offset_m, 0.0)
	velocity = reflected_direction \
		* incoming_velocity.length() \
		* retained_speed_ratio
	if maximum_upward_speed_mps > 0.0:
		velocity.y = minf(velocity.y, maximum_upward_speed_mps)
	var gravity_mps2 := _get_gravity_mps2()
	var time_to_water: Variant = BallisticMath.calculate_time_to_height(
		global_position.y,
		water_height_m,
		velocity.y,
		gravity_mps2
	)
	active_lifetime_seconds = maxf(
		float(time_to_water) + lifetime_margin_seconds,
		0.5
	) if time_to_water != null else maxf(
		fallback_lifetime_seconds,
		0.5
	)
	active_lifetime_seconds = minf(
		active_lifetime_seconds,
		maxf(emergency_maximum_lifetime_seconds, 0.5)
	)
	age_seconds = 0.0
	active = true
	water_impact_processed = false
	_despawn_requested = false
	show()
	set_physics_process(true)
	_orient_to_velocity()
	_start_trail()


func _physics_process(delta: float) -> void:
	if not active or delta <= 0.0:
		return
	var segment_start := global_position
	var gravity_mps2 := _get_gravity_mps2()
	var segment_end := BallisticMath.calculate_position(
		segment_start,
		velocity,
		gravity_mps2,
		delta
	)
	var next_velocity := velocity + Vector3.DOWN * gravity_mps2 * delta
	var water_hit := WaterIntersection.find_surface_intersection(
		self,
		segment_start,
		segment_end,
		water_height_m,
		_get_cached_ocean_manager()
	)
	if water_hit != null and water_hit.hit:
		global_position = water_hit.position
		velocity = velocity.lerp(
			next_velocity,
			water_hit.interpolation_ratio
		)
		_process_water_impact(water_hit)
		return
	global_position = segment_end
	velocity = next_velocity
	age_seconds += delta
	_orient_to_velocity()
	if age_seconds >= active_lifetime_seconds:
		despawn()


func _process_water_impact(hit: WaterSurfaceHit) -> void:
	if water_impact_processed:
		return
	water_impact_processed = true
	WaterImpactService.emit_impact(
		self,
		hit.position,
		_calculate_splash_strength(),
		velocity,
		hit.normal,
		events
	)
	despawn()


func _calculate_splash_strength() -> float:
	var speed_factor := clampf(velocity.length() / 800.0, 0.1, 1.0)
	return clampf(
		base_splash_strength * splash_strength_multiplier * speed_factor,
		0.05,
		1.5
	)


func despawn() -> void:
	if _despawn_requested:
		return
	_despawn_requested = true
	if pool_service != null and pool_service.release(self):
		return
	queue_free()


func on_spawned_from_pool() -> void:
	active = false
	active_lifetime_seconds = 0.0
	age_seconds = 0.0
	velocity = Vector3.ZERO
	water_height_m = 0.0
	water_impact_processed = false
	base_splash_strength = 1.0
	ocean_manager_ref = null
	pool_service = null
	events = null
	_despawn_requested = false
	hide()
	set_physics_process(false)
	_stop_trail()


func on_recycled_to_pool() -> void:
	active = false
	active_lifetime_seconds = 0.0
	age_seconds = 0.0
	velocity = Vector3.ZERO
	water_height_m = 0.0
	water_impact_processed = false
	base_splash_strength = 1.0
	ocean_manager_ref = null
	pool_service = null
	events = null
	_despawn_requested = true
	hide()
	set_physics_process(false)
	_stop_trail()


func _get_gravity_mps2() -> float:
	return float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	)) * maxf(gravity_scale, 0.0)


func _cache_ocean_manager(provided_manager: Node = null) -> void:
	ocean_manager_ref = null
	var manager := provided_manager
	if not is_instance_valid(manager) and get_tree() != null:
		manager = get_tree().get_first_node_in_group(&"ocean_manager")
	if is_instance_valid(manager):
		ocean_manager_ref = weakref(manager)


func _get_cached_ocean_manager() -> Node:
	return ocean_manager_ref.get_ref() as Node \
		if ocean_manager_ref != null else null


func _orient_to_velocity() -> void:
	if velocity.length_squared() <= 0.000001:
		return
	var direction := velocity.normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.98:
		up = Vector3.RIGHT
	look_at(global_position + direction, up)


func _configure_trail() -> void:
	if trail_particles == null:
		return
	trail_particles.amount = 72
	trail_particles.lifetime = trail_lifetime_seconds
	trail_particles.local_coords = false
	trail_particles.one_shot = false
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.ZERO
	process_material.spread = 0.0
	process_material.initial_velocity_min = 0.0
	process_material.initial_velocity_max = 0.0
	process_material.gravity = Vector3.ZERO
	process_material.scale_min = 0.25
	process_material.scale_max = 0.65
	var fade_gradient := Gradient.new()
	fade_gradient.set_color(0, trail_color)
	fade_gradient.set_color(
		1,
		Color(trail_color.r, trail_color.g, trail_color.b, 0.0)
	)
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade_gradient
	process_material.color_ramp = fade_texture
	trail_particles.process_material = process_material
	var trail_mesh := QuadMesh.new()
	trail_mesh.size = Vector2(2.2, 2.2)
	var trail_material := StandardMaterial3D.new()
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	trail_material.vertex_color_use_as_albedo = true
	trail_material.emission_enabled = true
	trail_material.emission = trail_color
	trail_material.emission_energy_multiplier = 2.0
	trail_mesh.material = trail_material
	trail_particles.draw_pass_1 = trail_mesh


func _start_trail() -> void:
	if trail_particles == null:
		return
	trail_particles.restart()
	trail_particles.emitting = true


func _stop_trail() -> void:
	if trail_particles == null:
		return
	trail_particles.emitting = false
	trail_particles.restart()
