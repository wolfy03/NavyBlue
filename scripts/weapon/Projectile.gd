extends ProjectileBase
class_name Projectile

const LIFETIME_SECONDS := 30.0
const MAX_SKIPPED_DYNAMIC_SOURCE_COLLIDERS := 16
const DEFAULT_AP_SHELL: ShellStats = preload(
	"res://scripts/combat/default_ap_shell.tres"
)

enum DespawnReason {
	NONE,
	WATER_IMPACT,
	LIFETIME_EXPIRED,
	SHIP_HIT,
	INVALID_DATA,
	POOL_RECYCLE,
	WORLD_OBSTACLE,
}

signal ship_hit_resolved(result: DamageResult)

@export_flags_3d_physics var shell_collision_mask := 1
@export_range(1, 16, 1) var max_skipped_ignored_colliders := 4
@export var water_height := 0.0
@export var base_water_splash_strength := 1.0
@export var min_water_splash_strength := 0.35
@export var max_water_splash_strength := 4.0
@export var velocity_strength_reference := 800.0
@export var ricochet_visual_scene: PackedScene = preload(
	"res://scenes/weapon/projectiles/ricochet_projectile_visual.tscn"
)
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
@export_category("Debug")

# Compatibility values retained as plain runtime data. Shells use direct
# Node3D ballistic integration rather than Jolt body velocity.
var gravity_scale := 1.0
var mass := 1.0

var team: StringName = &"neutral"
var velocity := Vector3.ZERO
var initial_velocity := Vector3.ZERO
var age_seconds := 0.0
var previous_position := Vector3.ZERO
var launch_position := Vector3.ZERO
var target_aim_point := Vector3.ZERO
var last_despawn_position := Vector3.ZERO
var active := false
var impact_processed := false
var water_impact_processed := false
var collision_excludes: Array[RID] = []
var ocean_manager_ref: WeakRef
var despawn_reason: DespawnReason = DespawnReason.NONE
var last_despawn_reason: DespawnReason = DespawnReason.NONE

var _despawn_requested := false
var _default_splash_strength := 1.0
var _collision_mask_warning_emitted := false

@onready var trail_particles: GPUParticles3D = get_node_or_null(
	"TrailParticles"
) as GPUParticles3D


func _ready() -> void:
	_default_splash_strength = base_water_splash_strength
	_validate_collision_mask()
	_configure_trail()
	_stop_trail()
	set_physics_process(false)


func _on_configured() -> void:
	var shell_data := projectile_data as ShellProjectileData
	if shell_data == null:
		return
	gravity_scale = shell_data.gravity_scale
	mass = maxf(shell_data.mass_kg, 0.01)
	lifetime_seconds = shell_data.lifetime_seconds
	base_water_splash_strength = shell_data.splash_strength
	explosion_radius = shell_data.explosion_radius
	shell_stats = _make_shell_stats(shell_data)


func _on_launched(context: ProjectileLaunchContext) -> void:
	team = context.source_team
	target_aim_point = context.aim_point
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
	_begin_flight(context.initial_velocity, context.aim_point)


func _begin_flight(
		start_velocity: Vector3,
		aim_point: Vector3
) -> void:
	velocity = start_velocity
	initial_velocity = start_velocity
	target_aim_point = aim_point
	age_seconds = 0.0
	impact_processed = false
	water_impact_processed = false
	despawn_reason = DespawnReason.NONE
	last_despawn_reason = DespawnReason.NONE
	_despawn_requested = false
	previous_position = global_position
	launch_position = global_position
	last_despawn_position = global_position
	_cache_collision_excludes()
	_cache_ocean_manager()
	_validate_collision_mask()
	active = true
	show()
	set_physics_process(true)
	_orient_to_velocity()
	_start_trail()


func _physics_process(delta: float) -> void:
	if not active or impact_processed or delta <= 0.0:
		return
	if projectile_data != null and not projectile_data is ShellProjectileData:
		despawn_with_reason(DespawnReason.INVALID_DATA)
		return
	var segment_start := global_position
	var gravity_mps2 := get_effective_gravity_mps2()
	var segment_end := BallisticMath.calculate_position(
		segment_start,
		velocity,
		gravity_mps2,
		delta
	)
	var next_velocity := velocity + Vector3.DOWN * gravity_mps2 * delta
	var collision := _find_first_collision(segment_start, segment_end)
	previous_position = segment_start
	if collision.hit:
		var impact_ratio := clampf(collision.ratio, 0.0, 1.0)
		global_position = collision.position
		velocity = velocity.lerp(next_velocity, impact_ratio)
		age_seconds += delta * impact_ratio
		_process_collision(collision)
		return
	global_position = segment_end
	velocity = next_velocity
	age_seconds += delta
	_orient_to_velocity()
	if age_seconds >= lifetime_seconds:
		despawn_with_reason(DespawnReason.LIFETIME_EXPIRED)


func get_effective_gravity_mps2() -> float:
	return BallisticMath.get_effective_gravity_mps2(
		projectile_data as ShellProjectileData,
		gravity_scale
	)


func _find_first_collision(
		segment_start: Vector3,
		segment_end: Vector3
) -> ShellCollisionResult:
	var ship_hit := _query_ship_collision(segment_start, segment_end)
	var water_hit := _query_water_collision(segment_start, segment_end)
	if ship_hit.hit and water_hit.hit:
		return ship_hit if ship_hit.ratio <= water_hit.ratio else water_hit
	if ship_hit.hit:
		return ship_hit
	return water_hit


func _query_ship_collision(
		segment_start: Vector3,
		segment_end: Vector3
) -> ShellCollisionResult:
	# TODO: If visual misses appear around thin hull geometry, replace this ray
	# query with a shared SphereShape3D motion query.
	var result := ShellCollisionResult.new()
	var world := get_world_3d()
	if world == null \
			or shell_collision_mask == 0 \
			or segment_start.is_equal_approx(segment_end):
		return result
	var excludes: Array[RID] = collision_excludes.duplicate()
	var skipped_ignored_colliders := 0
	var skipped_source_colliders := 0
	var maximum_attempts := max_skipped_ignored_colliders \
		+ MAX_SKIPPED_DYNAMIC_SOURCE_COLLIDERS \
		+ 1
	for _attempt in range(maximum_attempts):
		var query := PhysicsRayQueryParameters3D.create(
			segment_start,
			segment_end,
			shell_collision_mask,
			excludes
		)
		query.collide_with_bodies = true
		query.collide_with_areas = true
		query.hit_from_inside = true
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return result
		var collider: Object = hit.get("collider")
		var target_ship := _find_ship_damage_target(collider)
		if target_ship != null:
			if _is_source_ship(target_ship):
				if skipped_source_colliders \
						>= MAX_SKIPPED_DYNAMIC_SOURCE_COLLIDERS:
					return result
				var source_collision_object := collider as CollisionObject3D
				if source_collision_object == null:
					return result
				var source_rid := source_collision_object.get_rid()
				if source_rid.is_valid() and not excludes.has(source_rid):
					excludes.append(source_rid)
				skipped_source_colliders += 1
				continue
			result.hit = true
			result.type = ShellCollisionResult.Type.SHIP
			result.target_ship = target_ship
			_apply_ray_hit_to_result(
				result,
				hit,
				collider,
				segment_start,
				segment_end
			)
			return result
		if not _should_ignore_shell_collider(collider):
			result.hit = true
			result.type = ShellCollisionResult.Type.WORLD_OBSTACLE
			_apply_ray_hit_to_result(
				result,
				hit,
				collider,
				segment_start,
				segment_end
			)
			return result
		if skipped_ignored_colliders >= max_skipped_ignored_colliders:
			return result
		var collision_object := collider as CollisionObject3D
		if collision_object == null:
			return result
		var rid := collision_object.get_rid()
		if rid.is_valid() and not excludes.has(rid):
			excludes.append(rid)
		skipped_ignored_colliders += 1
	return result


func _query_water_collision(
		segment_start: Vector3,
		segment_end: Vector3
) -> ShellCollisionResult:
	var result := ShellCollisionResult.new()
	var hit := WaterIntersection.find_surface_intersection(
		self,
		segment_start,
		segment_end,
		water_height,
		_get_cached_ocean_manager()
	)
	if hit == null or not hit.hit:
		return result
	result.hit = true
	result.type = ShellCollisionResult.Type.WATER
	result.ratio = hit.interpolation_ratio
	result.position = hit.position
	result.normal = hit.normal
	return result


func _process_collision(collision: ShellCollisionResult) -> void:
	if collision == null or not collision.hit:
		return
	match collision.type:
		ShellCollisionResult.Type.SHIP:
			_process_ship_hit(collision)
		ShellCollisionResult.Type.WATER:
			_process_water_hit(collision)
		ShellCollisionResult.Type.WORLD_OBSTACLE:
			_process_world_obstacle_hit(collision)


func _process_ship_hit(collision: ShellCollisionResult) -> void:
	if impact_processed or collision.target_ship == null:
		return
	impact_processed = true
	active = false
	var direction := velocity.normalized()
	if direction.length_squared() <= 0.000001:
		direction = -global_transform.basis.z.normalized()
	var hit_normal := collision.normal.normalized()
	if hit_normal.length_squared() <= 0.000001:
		hit_normal = -direction
	elif hit_normal.dot(direction) > 0.0:
		hit_normal = -hit_normal
	var hit_info := HitInfo.new().setup(
		shell_stats,
		collision.target_ship,
		collision.position,
		hit_normal,
		direction,
		_determine_armor_part(
			collision.target_ship,
			collision.position,
			hit_normal
		)
	)
	hit_info.set_damage_source(
		get_source_ship(),
		source_ship_instance_id,
		source_weapon_id
	)
	hit_info.projectile_info = _get_projectile_damage_info()
	var damage_request := DamageRequest.from_hit_info(hit_info)
	damage_request.source_team = source_team
	damage_request.projectile_data = projectile_data
	damage_request.relative_velocity = velocity
	var damage_result := ShipDamageResolver.resolve(damage_request)
	if battle_services != null:
		battle_services.events.emit_damage_applied(damage_result)
		battle_services.events.emit_shell_hit(
			self,
			collision.target_ship,
			collision.position,
			hit_normal,
			damage_result
		)
	var impact_result := ProjectileImpactResult.new()
	impact_result.surface_type = ProjectileImpactResult.SurfaceType.SHIP
	impact_result.hit_position = collision.position
	impact_result.hit_normal = hit_normal
	impact_result.incoming_velocity = velocity
	impact_result.target = collision.target_ship
	impact_result.damage_result = damage_result
	emit_impact(impact_result)
	ship_hit_resolved.emit(damage_result)
	if damage_result.hit_outcome == HitOutcome.Type.RICOCHET:
		_spawn_ricochet_visual(
			collision.position,
			hit_normal,
			velocity
		)
	despawn_with_reason(DespawnReason.SHIP_HIT)


func _process_water_hit(collision: ShellCollisionResult) -> void:
	if water_impact_processed:
		return
	water_impact_processed = true
	impact_processed = true
	active = false
	var impact_result := ProjectileImpactResult.new()
	impact_result.surface_type = ProjectileImpactResult.SurfaceType.WATER
	impact_result.hit_position = collision.position
	impact_result.hit_normal = collision.normal
	impact_result.incoming_velocity = velocity
	impact_result.impact_strength = _calculate_water_impact_strength()
	emit_impact(impact_result)
	despawn_with_reason(DespawnReason.WATER_IMPACT)


func _process_world_obstacle_hit(collision: ShellCollisionResult) -> void:
	if impact_processed:
		return
	impact_processed = true
	active = false
	var impact_result := ProjectileImpactResult.new()
	impact_result.surface_type = ProjectileImpactResult.SurfaceType.TERRAIN
	impact_result.hit_position = collision.position
	impact_result.hit_normal = collision.normal
	impact_result.incoming_velocity = velocity
	emit_impact(impact_result)
	despawn_with_reason(DespawnReason.WORLD_OBSTACLE)


func _spawn_ricochet_visual(
		hit_position: Vector3,
		hit_normal: Vector3,
		incoming_velocity: Vector3
) -> void:
	if ricochet_visual_scene == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var visual: Node
	if battle_services != null:
		var acquire_result := battle_services.projectile_pool.acquire_result(
			ricochet_visual_scene,
			parent,
			true
		)
		visual = acquire_result.instance
	if visual == null:
		visual = ricochet_visual_scene.instantiate()
		if visual != null:
			parent.add_child(visual)
	var ricochet := visual as RicochetProjectileVisual
	if ricochet == null:
		if visual != null:
			visual.queue_free()
		return
	ricochet.launch(
		hit_position,
		incoming_velocity,
		hit_normal,
		WaterIntersection.get_water_height(
			self,
			hit_position,
			water_height,
			_get_cached_ocean_manager()
		),
		base_water_splash_strength,
		_get_cached_ocean_manager(),
		battle_services.projectile_pool if battle_services != null else null,
		battle_services.events if battle_services != null else null
	)


func _cache_collision_excludes() -> void:
	collision_excludes.clear()
	var source_ship := get_source_ship()
	if source_ship == null:
		return
	_append_collision_rid(source_ship)
	for child in source_ship.find_children(
			"*",
			"CollisionObject3D",
			true,
			false
	):
		_append_collision_rid(child)


func _append_collision_rid(value: Variant) -> void:
	var collision_object := value as CollisionObject3D
	if collision_object == null:
		return
	var rid := collision_object.get_rid()
	if rid.is_valid() and not collision_excludes.has(rid):
		collision_excludes.append(rid)


func _should_ignore_shell_collider(collider: Object) -> bool:
	var candidate := collider as Node
	while candidate != null:
		if candidate.is_in_group(&"shell_ignored") \
				or candidate.is_in_group(&"projectile_sensor") \
				or candidate.is_in_group(&"selection_area"):
			return true
		candidate = candidate.get_parent()
	# TODO: Move ignored projectile sensors to a dedicated collision layer
	# and exclude that layer from the shell collision mask.
	return false


func _is_source_ship(target_ship: Node) -> bool:
	if target_ship == null or not is_instance_valid(target_ship):
		return false
	var source_ship := get_source_ship()
	if source_ship != null \
			and is_instance_valid(source_ship) \
			and target_ship == source_ship:
		return true
	return source_ship_instance_id != 0 \
		and target_ship.get_instance_id() == source_ship_instance_id


func _apply_ray_hit_to_result(
		result: ShellCollisionResult,
		hit: Dictionary,
		collider: Object,
		segment_start: Vector3,
		segment_end: Vector3
) -> void:
	result.position = hit.get("position", segment_end)
	result.normal = hit.get("normal", Vector3.UP)
	result.collider = collider
	var segment_length := segment_start.distance_to(segment_end)
	result.ratio = segment_start.distance_to(result.position) \
		/ segment_length if segment_length > 0.00001 else 0.0


func _cache_ocean_manager() -> void:
	ocean_manager_ref = null
	if get_tree() == null:
		return
	var manager := get_tree().get_first_node_in_group(&"ocean_manager")
	if manager != null:
		ocean_manager_ref = weakref(manager)


func _get_cached_ocean_manager() -> Node:
	return ocean_manager_ref.get_ref() as Node \
		if ocean_manager_ref != null else null


func _validate_collision_mask(report_warning: bool = true) -> bool:
	if shell_collision_mask != 0:
		return true
	if report_warning and not _collision_mask_warning_emitted:
		_collision_mask_warning_emitted = true
		push_warning("Shell projectile collision mask is empty.")
	return false


func debug_validate_collision_setup(
		ship_hull: CollisionObject3D = null,
		selection_area: CollisionObject3D = null,
		projectile_sensor: CollisionObject3D = null,
		world_obstacle: CollisionObject3D = null,
		water_area: CollisionObject3D = null
) -> Array[String]:
	var issues: Array[String] = []
	if shell_collision_mask == 0:
		issues.append("Shell collision mask is empty")
	if ship_hull != null and not _is_layer_in_shell_mask(ship_hull):
		issues.append("Ship hull collision layer is not included")
	if selection_area != null \
			and _is_layer_in_shell_mask(selection_area) \
			and not _should_ignore_shell_collider(selection_area):
		issues.append(
			"Selection area is included but not marked ignored"
		)
	if projectile_sensor != null \
			and _is_layer_in_shell_mask(projectile_sensor) \
			and not _should_ignore_shell_collider(projectile_sensor):
		issues.append(
			"Projectile sensor is included but not marked ignored"
		)
	if world_obstacle != null \
			and not _is_layer_in_shell_mask(world_obstacle):
		issues.append("World obstacle collision layer is not included")
	if water_area != null \
			and _is_layer_in_shell_mask(water_area) \
			and not _should_ignore_shell_collider(water_area):
		issues.append(
			"Water area is included as a duplicate shell collision target"
		)
	return issues


func _is_layer_in_shell_mask(collision_object: CollisionObject3D) -> bool:
	return collision_object != null \
		and (shell_collision_mask & collision_object.collision_layer) != 0


func despawn() -> void:
	despawn_with_reason(DespawnReason.POOL_RECYCLE)


func despawn_with_reason(reason: DespawnReason) -> void:
	if _despawn_requested:
		return
	_despawn_requested = true
	active = false
	despawn_reason = reason
	last_despawn_reason = reason
	last_despawn_position = global_position
	_log_despawn(reason, global_position)
	recycle_projectile()


func on_spawned_from_pool() -> void:
	super.on_spawned_from_pool()
	_despawn_requested = false
	team = &"neutral"
	velocity = Vector3.ZERO
	initial_velocity = Vector3.ZERO
	age_seconds = 0.0
	previous_position = global_position
	launch_position = global_position
	target_aim_point = Vector3.ZERO
	last_despawn_position = global_position
	active = false
	impact_processed = false
	water_impact_processed = false
	collision_excludes.clear()
	ocean_manager_ref = null
	despawn_reason = DespawnReason.NONE
	last_despawn_reason = DespawnReason.NONE
	shell_stats = DEFAULT_AP_SHELL
	gravity_scale = 1.0
	mass = 1.0
	lifetime_seconds = LIFETIME_SECONDS
	base_water_splash_strength = _default_splash_strength
	explosion_radius = 0.0
	hide()
	set_physics_process(false)
	_stop_trail()


func on_recycled_to_pool() -> void:
	_despawn_requested = true
	team = &"neutral"
	active = false
	velocity = Vector3.ZERO
	initial_velocity = Vector3.ZERO
	age_seconds = 0.0
	previous_position = global_position
	launch_position = global_position
	target_aim_point = Vector3.ZERO
	impact_processed = false
	water_impact_processed = false
	collision_excludes.clear()
	ocean_manager_ref = null
	shell_stats = DEFAULT_AP_SHELL
	gravity_scale = 1.0
	mass = 1.0
	lifetime_seconds = LIFETIME_SECONDS
	base_water_splash_strength = _default_splash_strength
	explosion_radius = 0.0
	hide()
	set_physics_process(false)
	_stop_trail()
	super.on_recycled_to_pool()


func _on_reset_for_pool() -> void:
	_despawn_requested = true
	team = FactionRelations.NEUTRAL
	active = false
	velocity = Vector3.ZERO
	initial_velocity = Vector3.ZERO
	age_seconds = 0.0
	previous_position = global_position
	launch_position = global_position
	target_aim_point = Vector3.ZERO
	impact_processed = false
	water_impact_processed = false
	collision_excludes.clear()
	ocean_manager_ref = null
	shell_stats = DEFAULT_AP_SHELL
	gravity_scale = 1.0
	mass = 1.0
	lifetime_seconds = LIFETIME_SECONDS
	base_water_splash_strength = _default_splash_strength
	explosion_radius = 0.0
	_stop_trail()


func _make_shell_stats(data: ShellProjectileData) -> ShellStats:
	var stats := DEFAULT_AP_SHELL.duplicate(true) as ShellStats
	stats.shell_type = data.shell_type
	stats.penetration = data.penetration
	stats.base_damage = data.damage
	stats.penetration_damage_multiplier = data.penetration_damage_multiplier
	stats.non_penetration_damage_multiplier = \
		data.non_penetration_damage_multiplier
	stats.ricochet_damage_multiplier = data.ricochet_damage_multiplier
	stats.explosion_damage = data.damage * data.ricochet_damage_multiplier \
		if stats.shell_type == ShellStats.ShellType.HE else 0.0
	stats.explosion_radius = data.explosion_radius
	return stats


func _get_projectile_damage_info() -> Dictionary:
	if projectile_data == null:
		return {
			"projectile_id": "legacy_shell",
			"projectile_type": String(shell_stats.get_shell_type_name()) \
				if shell_stats != null else "unknown",
			"damage": shell_stats.base_damage if shell_stats != null else 0.0,
			"penetration": shell_stats.penetration \
				if shell_stats != null else 0.0,
			"source_ship_instance_id": source_ship_instance_id,
			"weapon_id": source_weapon_id,
		}
	return {
		"projectile_id": projectile_data.id,
		"projectile_type": "he" if (
			projectile_data is ShellProjectileData
			and (projectile_data as ShellProjectileData).shell_type \
				== ShellStats.ShellType.HE
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


func _find_ship_damage_target(collider: Object) -> Node3D:
	if not collider is Node:
		return null
	var candidate := collider as Node
	while candidate != null:
		if candidate is Node3D \
				and candidate.has_method(&"get_defense_stats") \
				and (
					candidate.has_method(&"apply_damage_result")
					or candidate.has_method(&"apply_damage")
				):
			return candidate as Node3D
		candidate = candidate.get_parent()
	return null


func _determine_armor_part(
		target_ship: Node3D,
		hit_position: Vector3,
		hit_normal: Vector3
) -> ArmorPart.Type:
	var local_position := target_ship.to_local(hit_position)
	var local_normal := (
		target_ship.global_transform.basis.inverse() * hit_normal
	).normalized()
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
	var end_threshold := hull_size.z * 0.5 * end_section_ratio
	if local_position.z <= -end_threshold:
		return ArmorPart.Type.BOW
	if local_position.z >= end_threshold:
		return ArmorPart.Type.STERN
	return ArmorPart.Type.BELT


func _calculate_water_impact_strength() -> float:
	var speed_factor := clampf(
		velocity.length() / maxf(velocity_strength_reference, 0.001),
		0.25,
		3.0
	)
	var mass_factor := sqrt(maxf(mass, 0.1))
	return clampf(
		base_water_splash_strength * mass_factor * speed_factor,
		min_water_splash_strength,
		max_water_splash_strength
	)


func _orient_to_velocity() -> void:
	if velocity.length_squared() <= 0.000001:
		return
	var direction := velocity.normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.98:
		up = Vector3.RIGHT
	look_at(global_position + direction, up)


func _log_despawn(reason: DespawnReason, position: Vector3) -> void:
	if battle_services == null \
			or battle_services.debug_settings == null \
			or not battle_services.debug_settings.log_projectile_lifecycle:
		return
	var distance_xz := CombatGeometryXZ.distance_xz(
		launch_position,
		position
	)
	var target_error := CombatGeometryXZ.distance_xz(
		position,
		target_aim_point
	) if target_aim_point.is_finite() else -1.0
	print(
		(
			"[ShellFlight] weapon=%s projectile=%s reason=%s "
			+ "distance_xz=%.1f age=%.2f initial_speed=%.1f "
			+ "speed=%.1f target_error=%.1f position=%s"
		) % [
			source_weapon_id,
			projectile_data.id if projectile_data != null else "unknown",
			DespawnReason.keys()[reason],
			distance_xz,
			age_seconds,
			initial_velocity.length(),
			velocity.length(),
			target_error,
			position,
		]
	)


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
	fade_gradient.set_color(0, trail_color)
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
