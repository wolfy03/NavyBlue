extends "res://scripts/weapon/projectile/WeaponProjectileBase.gd"
class_name Projectile

const LIFETIME_SECONDS := 30.0
const DEFAULT_AP_SHELL: ShellStats = preload("res://scripts/combat/default_ap_shell.tres")

signal ship_hit_resolved(result: DamageResult)

@export var water_height := 0.0
@export var base_water_splash_strength := 1.0
@export var min_water_splash_strength := 0.35
@export var max_water_splash_strength := 4.0
@export var velocity_strength_reference := 800.0
@export_category("Visual Trail")
@export var projectile_trail_enabled := true
@export_range(0.1, 3.0, 0.05, "or_greater") var trail_lifetime_sec := 1.15
@export_range(0.5, 20.0, 0.25, "or_greater") var trail_width_m := 5.0
@export_range(16, 384, 1, "or_greater") var trail_particle_count := 160
@export var trail_color := Color(1.0, 0.66, 0.24, 0.9)
@export var shell_stats: ShellStats = DEFAULT_AP_SHELL
@export var lifetime_seconds: float = LIFETIME_SECONDS
@export var explosion_radius: float = 0.0
@export_range(0.0, 1.0, 0.01) var deck_normal_threshold: float = 0.65
@export_range(0.1, 1.0, 0.01) var end_section_ratio: float = 0.68
@export_range(0.1, 3.0, 0.05) var superstructure_height_ratio: float = 1.05

var team: StringName = &"neutral"
var age := 0.0
var previous_position := Vector3.ZERO
var previous_position_initialized := false
var water_impact_processed := false
var ship_impact_processed: bool = false
var last_travel_direction: Vector3 = Vector3.FORWARD
var _default_splash_strength: float = 1.0
@onready var trail_particles: GPUParticles3D = get_node_or_null("TrailParticles") \
	as GPUParticles3D

func _ready() -> void:
	super._ready()
	_default_splash_strength = base_water_splash_strength
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	previous_position = global_position
	previous_position_initialized = true
	_configure_trail()
	_stop_trail()
	if projectile_data != null:
		setup_projectile_data(projectile_data)

func setup_projectile_data(data: ProjectileData) -> void:
	super.setup_projectile_data(data)
	var shell_data := projectile_data as ShellProjectileData
	if shell_data == null:
		return
	gravity_scale = shell_data.gravity_scale
	mass = maxf(shell_data.mass_kg, 0.01)
	lifetime_seconds = shell_data.lifetime_seconds
	base_water_splash_strength = shell_data.splash_strength
	explosion_radius = shell_data.explosion_radius
	shell_stats = _make_shell_stats(shell_data)

func launch(
		start_velocity: Vector3,
		owner_team: StringName,
		fired_shell_stats: ShellStats = null,
		source_ship: Node = null,
	weapon_id: StringName = StringName()
) -> void:
	team = owner_team
	_apply_launch_source(source_ship, owner_team, weapon_id)
	linear_velocity = start_velocity
	if start_velocity.length_squared() > 0.000001:
		last_travel_direction = start_velocity.normalized()
	if fired_shell_stats != null:
		shell_stats = fired_shell_stats
	age = 0.0
	water_impact_processed = false
	ship_impact_processed = false
	_despawn_requested = false
	previous_position = global_position
	previous_position_initialized = true
	_start_trail()


func launch_with_context(context: ProjectileLaunchContext) -> void:
	if context == null:
		return
	super.launch_with_context(context)
	if shell_stats != null:
		shell_stats = shell_stats.duplicate(true) as ShellStats
		shell_stats.base_damage *= maxf(
			projectile_runtime_stats.damage_multiplier,
			0.0
		)
		shell_stats.explosion_damage *= maxf(
			projectile_runtime_stats.damage_multiplier,
			0.0
		)
	launch(
		context.initial_velocity,
		context.source_team,
		null,
		context.source_ship,
		context.source_weapon_id
	)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if ship_impact_processed:
		return
	for contact_index: int in state.get_contact_count():
		var collider: Object = state.get_contact_collider_object(contact_index)
		var target_ship: Node3D = _find_ship_damage_target(collider)
		if target_ship == null:
			continue
		_process_ship_contact(state, contact_index, target_ship)
		return

func _physics_process(delta: float) -> void:
	if ship_impact_processed:
		return
	if linear_velocity.length_squared() > 0.000001:
		last_travel_direction = linear_velocity.normalized()
	age += delta
	var current_position := global_position
	if not previous_position_initialized:
		previous_position = current_position
		previous_position_initialized = true

	if not water_impact_processed and _try_process_water_impact(previous_position, current_position):
		despawn()
		return

	var ocean_manager := _get_ocean_manager()
	if ocean_manager != null and ocean_manager.has_method(&"is_underwater"):
		if bool(ocean_manager.call(&"is_underwater", current_position)):
			_emit_water_impact(current_position, _calculate_water_impact_strength())
			despawn()
			return
	elif current_position.y <= water_height:
		_emit_water_impact(current_position, _calculate_water_impact_strength())
		despawn()
		return

	if age >= lifetime_seconds:
		despawn()
		return

	previous_position = current_position


func _process_ship_contact(
		state: PhysicsDirectBodyState3D,
		contact_index: int,
		target_ship: Node3D
) -> void:
	ship_impact_processed = true
	var direction: Vector3 = last_travel_direction
	if direction.length_squared() <= 0.000001:
		direction = state.linear_velocity.normalized()
	if direction.length_squared() <= 0.000001:
		direction = -global_transform.basis.z.normalized()
	var hit_position: Vector3 = state.get_contact_local_position(contact_index)
	var hit_normal: Vector3 = state.get_contact_local_normal(contact_index).normalized()
	if hit_normal.length_squared() <= 0.000001:
		hit_normal = -direction
	elif hit_normal.dot(direction) > 0.0:
		hit_normal = -hit_normal

	var hit_info := HitInfo.new().setup(
		shell_stats,
		target_ship,
		hit_position,
		hit_normal,
		direction,
		_determine_armor_part(target_ship, hit_position, hit_normal)
	)
	hit_info.set_damage_source(
		_get_source_ship(),
		source_ship_instance_id,
		source_weapon_id
	)
	hit_info.projectile_info = _get_projectile_damage_info()
	var damage_result: DamageResult = DamageResolver.resolve_hit(hit_info)
	ship_hit_resolved.emit(damage_result)
	call_deferred(&"despawn")

func on_spawned_from_pool() -> void:
	super.on_spawned_from_pool()
	age = 0.0
	water_impact_processed = false
	ship_impact_processed = false
	previous_position = global_position
	previous_position_initialized = true
	shell_stats = DEFAULT_AP_SHELL
	gravity_scale = 1.0
	mass = 1.0
	lifetime_seconds = LIFETIME_SECONDS
	base_water_splash_strength = _default_splash_strength
	explosion_radius = 0.0
	contact_monitor = true
	max_contacts_reported = 4
	_stop_trail()

func on_recycled_to_pool() -> void:
	_stop_trail()
	super.on_recycled_to_pool()
	team = &"neutral"


func _configure_trail() -> void:
	if trail_particles == null:
		return
	trail_particles.amount = trail_particle_count
	trail_particles.lifetime = trail_lifetime_sec
	trail_particles.local_coords = false
	trail_particles.one_shot = false
	trail_particles.fixed_fps = 30
	trail_particles.fract_delta = true
	var trail_extent := maxf(
		1200.0,
		velocity_strength_reference * trail_lifetime_sec * 1.6
	)
	trail_particles.visibility_aabb = AABB(
		Vector3.ONE * -trail_extent,
		Vector3.ONE * trail_extent * 2.0
	)

	var particle_material := ParticleProcessMaterial.new()
	particle_material.direction = Vector3.ZERO
	particle_material.spread = 0.0
	particle_material.initial_velocity_min = 0.0
	particle_material.initial_velocity_max = 0.0
	particle_material.gravity = Vector3.ZERO
	particle_material.scale_min = 0.45
	particle_material.scale_max = 1.0
	var fade_gradient := Gradient.new()
	fade_gradient.set_color(
		0,
		Color(trail_color.r, trail_color.g, trail_color.b, trail_color.a)
	)
	fade_gradient.set_color(
		1,
		Color(trail_color.r, trail_color.g, trail_color.b, 0.0)
	)
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade_gradient
	particle_material.color_ramp = fade_texture
	trail_particles.process_material = particle_material

	var trail_mesh := QuadMesh.new()
	trail_mesh.size = Vector2(trail_width_m, trail_width_m)
	var trail_material := StandardMaterial3D.new()
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	trail_material.vertex_color_use_as_albedo = true
	trail_material.albedo_color = Color.WHITE
	trail_material.emission_enabled = true
	trail_material.emission = trail_color
	trail_material.emission_energy_multiplier = 2.6
	trail_mesh.material = trail_material
	trail_particles.draw_pass_1 = trail_mesh


func _start_trail() -> void:
	if trail_particles == null or not projectile_trail_enabled:
		return
	trail_particles.restart()
	trail_particles.emitting = true


func _stop_trail() -> void:
	if trail_particles == null:
		return
	trail_particles.emitting = false
	trail_particles.restart()

func _make_shell_stats(data: ShellProjectileData) -> ShellStats:
	var stats := DEFAULT_AP_SHELL.duplicate(true) as ShellStats
	stats.shell_type = data.shell_type
	stats.penetration = data.penetration
	stats.base_damage = data.damage
	stats.penetration_damage_multiplier = data.penetration_damage_multiplier
	stats.non_penetration_damage_multiplier = data.non_penetration_damage_multiplier
	stats.ricochet_damage_multiplier = data.ricochet_damage_multiplier
	stats.explosion_damage = data.damage * data.ricochet_damage_multiplier \
		if stats.shell_type == ShellStats.ShellType.HE else 0.0
	stats.explosion_radius = data.explosion_radius
	return stats

func _get_projectile_damage_info() -> Dictionary:
	if projectile_data == null:
		return {
			"projectile_id": "legacy_shell",
			"projectile_type": String(shell_stats.get_shell_type_name()) if shell_stats != null else "unknown",
			"damage": shell_stats.base_damage if shell_stats != null else 0.0,
			"penetration": shell_stats.penetration if shell_stats != null else 0.0,
			"source_ship_instance_id": source_ship_instance_id,
			"weapon_id": source_weapon_id,
		}
	return {
		"projectile_id": projectile_data.id,
		"projectile_type": "he" if (
			projectile_data is ShellProjectileData
			and (projectile_data as ShellProjectileData).shell_type == ShellStats.ShellType.HE
		) else "ap",
		"damage": shell_stats.base_damage \
			if shell_stats != null else projectile_data.damage,
		"damage_multiplier": projectile_runtime_stats.damage_multiplier,
		"penetration": (
			projectile_data as ShellProjectileData
		).penetration if projectile_data is ShellProjectileData else 0.0,
		"explosion_radius": projectile_data.explosion_radius,
		"source_ship_instance_id": source_ship_instance_id,
		"weapon_id": source_weapon_id,
	}


func _get_source_ship() -> Node:
	return get_source_ship()


func _find_ship_damage_target(collider: Object) -> Node3D:
	if not collider is Node:
		return null
	var candidate: Node = collider as Node
	while candidate != null:
		if candidate is Node3D \
				and candidate.has_method(&"get_defense_stats") \
				and candidate.has_method(&"apply_damage"):
			return candidate as Node3D
		candidate = candidate.get_parent()
	return null


func _determine_armor_part(
		target_ship: Node3D,
		hit_position: Vector3,
		hit_normal: Vector3
) -> ArmorPart.Type:
	var local_position: Vector3 = target_ship.to_local(hit_position)
	var local_normal: Vector3 = (target_ship.global_transform.basis.inverse() * hit_normal).normalized()
	if local_normal.y >= deck_normal_threshold:
		return ArmorPart.Type.DECK

	var hull_size := Vector3(2.0, 1.0, 6.0)
	var ship_data: Variant = target_ship.get(&"ship_data")
	if ship_data != null:
		var configured_hull_size: Variant = ship_data.get(&"hull_size")
		if configured_hull_size is Vector3:
			hull_size = configured_hull_size
	if local_position.y >= hull_size.y * superstructure_height_ratio:
		return ArmorPart.Type.SUPERSTRUCTURE

	var end_threshold: float = hull_size.z * 0.5 * end_section_ratio
	if local_position.z <= -end_threshold:
		return ArmorPart.Type.BOW
	if local_position.z >= end_threshold:
		return ArmorPart.Type.STERN
	return ArmorPart.Type.BELT


func _try_process_water_impact(from_position: Vector3, to_position: Vector3) -> bool:
	var ocean_manager := _get_ocean_manager()
	if ocean_manager == null:
		return false
	if not ocean_manager.has_method(&"did_cross_water_surface"):
		return false
	if not bool(ocean_manager.call(&"did_cross_water_surface", from_position, to_position)):
		return false

	var hit: RefCounted = ocean_manager.call(&"get_surface_intersection_hit", from_position, to_position)
	if hit == null or not bool(hit.get(&"hit")):
		return false

	water_impact_processed = true
	var interaction := _get_ocean_interaction()
	if interaction != null and interaction.has_method(&"register_impact_at"):
		interaction.call(
			&"register_impact_at",
			hit.get(&"position") as Vector3,
			_calculate_water_impact_strength(),
			linear_velocity,
			hit.get(&"normal") as Vector3,
			self
		)
	_emit_water_impact(hit.get(&"position") as Vector3, _calculate_water_impact_strength())
	return true

func _emit_water_impact(position: Vector3, strength: float) -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").projectile_water_impact.emit(position, strength)


func _calculate_water_impact_strength() -> float:
	var speed_factor := clampf(linear_velocity.length() / maxf(velocity_strength_reference, 0.001), 0.25, 3.0)
	var mass_factor := sqrt(maxf(mass, 0.1))
	var strength := base_water_splash_strength * mass_factor * speed_factor
	return clampf(strength, min_water_splash_strength, max_water_splash_strength)


func _get_ocean_manager() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("ocean_manager")


func _get_ocean_interaction() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("ocean_interaction")
