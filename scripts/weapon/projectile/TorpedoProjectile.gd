extends "res://scripts/weapon/projectile/WeaponProjectileBase.gd"
class_name TorpedoProjectile

signal hit_resolved(result: DamageResult)

enum LaunchPhase {
	AIRBORNE,
	WATER_ENTRY,
	ARMING,
	RUNNING,
	IMPACTED,
	EXPIRED,
}

@export_category("Visual Wake")
@export var wake_enabled := true
@export_range(1.0, 12.0, 0.1, "or_greater") var wake_lifetime_sec := 5.5
@export_range(32, 512, 1, "or_greater") var wake_particle_count := 240
@export var wake_width_m := 5.5
@export var wake_patch_length_m := 11.0
@export var wake_color := Color(0.74, 0.95, 1.0, 0.72)

var torpedo_data: TorpedoProjectileData
var speed_mps := 0.0
var travelled_distance_m := 0.0
var age_seconds := 0.0
var armed := false
var launch_position := Vector3.ZERO
var water_height_m := 0.0
var impact_processed := false
var target_ref: WeakRef
var previous_position := Vector3.ZERO
var desired_yaw_radians := 0.0
var launch_mode: TorpedoLaunchMode.Type = TorpedoLaunchMode.Type.SURFACE
var launch_phase: LaunchPhase = LaunchPhase.ARMING
var intended_launch_direction := Vector3.ZERO
var airborne_age_seconds := 0.0
var _running_collision_layer := 0
var _running_collision_mask := 0
@onready var wake_particles: GPUParticles3D = get_node_or_null("WakeParticles") \
	as GPUParticles3D


func _ready() -> void:
	super._ready()
	gravity_scale = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_configure_wake()
	_stop_wake()


func _on_configured() -> void:
	torpedo_data = projectile_data as TorpedoProjectileData


func _on_launched(context: ProjectileLaunchContext) -> void:
	if torpedo_data == null:
		push_warning("Torpedo launch requires TorpedoProjectileData and context.")
		despawn()
		return
	target_ref = null
	if torpedo_data.guidance_type \
			== TorpedoProjectileData.GuidanceType.PASSIVE_HOMING \
			and context.target != null \
			and is_instance_valid(context.target):
		target_ref = weakref(context.target)
	water_height_m = _resolve_water_height()
	launch_mode = context.torpedo_launch_mode
	intended_launch_direction = context.intended_launch_direction
	intended_launch_direction.y = 0.0
	_running_collision_layer = collision_layer
	_running_collision_mask = collision_mask
	if launch_mode == TorpedoLaunchMode.Type.AIR_DROPPED:
		_begin_airborne_launch(context)
		return
	_begin_surface_launch()


func _begin_surface_launch() -> void:
	var launch_transform := global_transform
	launch_transform.origin.y = water_height_m - torpedo_data.running_depth_m
	global_transform = launch_transform
	launch_position = launch_transform.origin
	speed_mps = torpedo_data.launch_speed_mps * maxf(
		projectile_runtime_stats.projectile_speed_multiplier,
		0.0
	)
	travelled_distance_m = 0.0
	age_seconds = 0.0
	armed = false
	impact_processed = false
	launch_phase = LaunchPhase.ARMING
	airborne_age_seconds = 0.0
	previous_position = launch_transform.origin
	var launch_direction := -launch_transform.basis.z
	launch_direction.y = 0.0
	if launch_direction.length_squared() < 0.0001:
		launch_direction = Vector3.FORWARD
	launch_direction = launch_direction.normalized()
	desired_yaw_radians = atan2(-launch_direction.x, -launch_direction.z)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_start_wake()


func _begin_airborne_launch(context: ProjectileLaunchContext) -> void:
	launch_phase = LaunchPhase.AIRBORNE
	launch_position = global_position
	speed_mps = 0.0
	travelled_distance_m = 0.0
	age_seconds = 0.0
	airborne_age_seconds = 0.0
	armed = false
	impact_processed = false
	previous_position = global_position
	gravity_scale = 1.0
	linear_velocity = context.initial_velocity
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_stop_wake()


func _physics_process(delta: float) -> void:
	if impact_processed or torpedo_data == null:
		return
	if launch_phase == LaunchPhase.AIRBORNE:
		_update_airborne(delta)
		return
	var segment_start := previous_position
	var segment_end := global_position
	var travelled_this_frame := CombatGeometryXZ.distance_xz(
		segment_start,
		segment_end
	)
	travelled_distance_m += travelled_this_frame
	age_seconds += delta
	speed_mps = move_toward(
		speed_mps,
		torpedo_data.max_speed_mps * maxf(
			projectile_runtime_stats.projectile_speed_multiplier,
			0.0
		),
		torpedo_data.acceleration_mps2 * delta
	)
	_update_guidance(delta)
	if not armed and travelled_distance_m >= torpedo_data.arming_distance_m:
		armed = true
		launch_phase = LaunchPhase.RUNNING
	if travelled_this_frame > 0.0001 \
			and _try_process_ship_proximity(segment_start, segment_end):
		return
	previous_position = segment_end
	var maximum_range := torpedo_data.maximum_range_m * maxf(
		projectile_runtime_stats.range_multiplier,
		0.0
	)
	if age_seconds >= torpedo_data.lifetime_seconds \
			or (maximum_range > 0.0 and travelled_distance_m >= maximum_range):
		launch_phase = LaunchPhase.EXPIRED
		despawn()


func _update_airborne(delta: float) -> void:
	airborne_age_seconds += delta
	if global_position.y <= water_height_m:
		_enter_water()
		return
	if airborne_age_seconds >= maxf(
		torpedo_data.airborne_timeout_sec,
		0.1
	):
		launch_phase = LaunchPhase.EXPIRED
		despawn()


func _enter_water() -> void:
	if launch_phase != LaunchPhase.AIRBORNE:
		return
	launch_phase = LaunchPhase.WATER_ENTRY
	var direction := intended_launch_direction
	if direction.length_squared() <= 0.0001:
		direction = linear_velocity
		direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = -global_basis.z
		direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		launch_phase = LaunchPhase.EXPIRED
		despawn()
		return
	direction = direction.normalized()
	desired_yaw_radians = atan2(-direction.x, -direction.z)
	var running_transform := global_transform
	running_transform.origin.y = water_height_m - torpedo_data.running_depth_m
	running_transform.basis = Basis.from_euler(
		Vector3(0.0, desired_yaw_radians, 0.0)
	)
	global_transform = running_transform
	launch_position = running_transform.origin
	previous_position = running_transform.origin
	gravity_scale = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = _running_collision_layer
	collision_mask = _running_collision_mask
	speed_mps = torpedo_data.launch_speed_mps * maxf(
		projectile_runtime_stats.projectile_speed_multiplier,
		0.0
	)
	travelled_distance_m = 0.0
	age_seconds = 0.0
	armed = false
	launch_phase = LaunchPhase.ARMING
	if battle_services != null:
		# Route the entry splash through the standard projectile-impact effect
		# path so CombatEffectPresenter spawns exactly one water splash. This is
		# emitted directly (not via emit_impact) so it does not consume the
		# projectile's one-shot impact reserved for the eventual ship hit.
		var water_impact := ProjectileImpactResult.new()
		water_impact.projectile = self
		water_impact.surface_type = ProjectileImpactResult.SurfaceType.WATER
		water_impact.hit_position = running_transform.origin
		water_impact.hit_normal = Vector3.UP
		water_impact.incoming_velocity = intended_launch_direction
		water_impact.impact_strength = torpedo_data.water_entry_effect_strength
		battle_services.events.emit_projectile_impact(water_impact)
	_start_wake()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if impact_processed or torpedo_data == null:
		return
	if launch_phase == LaunchPhase.AIRBORNE:
		return
	var next_transform := state.transform
	next_transform.origin.y = water_height_m - torpedo_data.running_depth_m
	next_transform.basis = Basis.from_euler(
		Vector3(0.0, desired_yaw_radians, 0.0)
	)
	state.transform = next_transform
	var direction := -next_transform.basis.z.normalized()
	state.linear_velocity = direction * speed_mps
	state.angular_velocity = Vector3.ZERO


func _update_guidance(delta: float) -> void:
	if torpedo_data.guidance_type \
			!= TorpedoProjectileData.GuidanceType.PASSIVE_HOMING \
			or torpedo_data.max_turn_rate_deg_sec <= 0.0 \
			or target_ref == null:
		return
	if torpedo_data.seeker_activation_distance_m > 0.0 \
			and travelled_distance_m \
				< torpedo_data.seeker_activation_distance_m:
		return
	var target := target_ref.get_ref() as Node3D
	if target == null or not is_instance_valid(target):
		target_ref = null
		return
	var direction := target.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	var target_distance := direction.length()
	if torpedo_data.seeker_range_m > 0.0 \
			and target_distance > torpedo_data.seeker_range_m:
		return
	var current_forward := -global_transform.basis.z
	current_forward.y = 0.0
	if current_forward.length_squared() < 0.01:
		return
	var field_of_view := clampf(
		torpedo_data.seeker_field_of_view_degrees,
		0.0,
		360.0
	)
	if field_of_view < 359.9:
		var target_angle := rad_to_deg(
			current_forward.normalized().angle_to(direction / target_distance)
		)
		if target_angle > field_of_view * 0.5:
			return
	var target_yaw := atan2(-direction.x, -direction.z)
	desired_yaw_radians = rotate_toward(
		desired_yaw_radians,
		target_yaw,
		deg_to_rad(torpedo_data.max_turn_rate_deg_sec) * delta
	)


func _on_body_entered(body: Node) -> void:
	if impact_processed or torpedo_data == null:
		return
	if launch_phase == LaunchPhase.AIRBORNE \
			or launch_phase == LaunchPhase.WATER_ENTRY:
		return
	var target_ship := _find_ship_target(body)
	if not _is_valid_torpedo_target(target_ship):
		return
	var intersection := _get_segment_hull_intersection_xz(
		target_ship,
		previous_position,
		global_position
	)
	var hit_position := intersection.position \
		if intersection.hit else global_position
	if CombatGeometryXZ.distance_xz(launch_position, hit_position) \
			< torpedo_data.arming_distance_m:
		return
	_resolve_ship_hit(target_ship, hit_position)


func _try_process_ship_proximity(
		segment_start: Vector3,
		segment_end: Vector3
) -> bool:
	if get_tree() == null:
		return false
	var nearest_target: ShipUnit
	var nearest_result: SegmentIntersectionResult
	for value in get_tree().get_nodes_in_group(&"ships"):
		var target_ship := value as ShipUnit
		if not _is_valid_torpedo_target(target_ship):
			continue
		var intersection := _get_segment_hull_intersection_xz(
			target_ship,
			segment_start,
			segment_end
		)
		if not intersection.hit:
			continue
		var hit_distance := CombatGeometryXZ.distance_xz(
			launch_position,
			intersection.position
		)
		if hit_distance < torpedo_data.arming_distance_m:
			continue
		if nearest_result == null \
				or intersection.ratio < nearest_result.ratio:
			nearest_target = target_ship
			nearest_result = intersection
	if nearest_target == null or nearest_result == null:
		return false
	_resolve_ship_hit(nearest_target, nearest_result.position)
	return true


func _resolve_ship_hit(
		target_ship: ShipUnit,
		hit_position: Vector3
) -> void:
	if impact_processed or target_ship == null:
		return
	impact_processed = true
	launch_phase = LaunchPhase.IMPACTED
	var direction := -global_transform.basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	var hit_info := HitInfo.new()
	hit_info.target_ship = target_ship
	hit_info.hit_position = hit_position
	hit_info.hit_normal = -direction
	hit_info.shell_direction = direction
	hit_info.armor_part = _determine_underwater_section(
		target_ship,
		hit_position
	)
	hit_info.damage_type = DamageType.Type.TORPEDO
	hit_info.torpedo_data = torpedo_data
	hit_info.projectile_info = {
		"projectile_id": torpedo_data.id,
		"projectile_type": "torpedo",
		"damage": torpedo_data.direct_damage + torpedo_data.explosion_damage,
		"damage_multiplier": projectile_runtime_stats.damage_multiplier,
		"flooding_chance_bonus": projectile_runtime_stats.flooding_chance_bonus,
		"source_ship_instance_id": source_ship_instance_id,
		"weapon_id": source_weapon_id,
	}
	hit_info.set_damage_source(
		get_source_ship(),
		source_ship_instance_id,
		source_weapon_id
	)
	var damage_request := DamageRequest.from_hit_info(hit_info)
	damage_request.source_team = source_team
	damage_request.projectile_data = projectile_data
	damage_request.relative_velocity = direction * speed_mps
	var result := ShipDamageResolver.resolve(damage_request)
	if battle_services != null:
		battle_services.events.emit_damage_applied(result)
	var impact_result := ProjectileImpactResult.new()
	impact_result.surface_type = ProjectileImpactResult.SurfaceType.SHIP
	impact_result.hit_position = hit_position
	impact_result.hit_normal = -direction
	impact_result.incoming_velocity = direction
	impact_result.target = target_ship
	impact_result.damage_result = result
	emit_impact(impact_result)
	hit_resolved.emit(result)
	if battle_services != null:
		battle_services.events.emit_torpedo_hit(
			self,
			target_ship,
			result
		)
	call_deferred(&"despawn")


func _get_segment_hull_intersection_xz(
		target_ship: ShipUnit,
		segment_start: Vector3,
		segment_end: Vector3
) -> SegmentIntersectionResult:
	if target_ship == null or target_ship.ship_data == null:
		return SegmentIntersectionResult.new()
	var half_extents := target_ship.ship_data.hull_size * 0.5
	return CombatGeometryXZ.segment_rectangle_intersection_xz(
		segment_start,
		segment_end,
		target_ship.global_transform,
		Vector2(half_extents.x + 0.75, half_extents.z + 0.75)
	)


func _is_valid_torpedo_target(target_ship: ShipUnit) -> bool:
	return target_ship != null \
		and is_instance_valid(target_ship) \
		and target_ship != get_source_ship() \
		and not target_ship.is_queued_for_deletion() \
		and target_ship.is_inside_tree() \
		and target_ship.is_alive() \
		and target_ship.ship_data != null \
		and FactionRelations.are_hostile(source_team, target_ship.team)


func _find_ship_target(body: Node) -> ShipUnit:
	var candidate := body
	while candidate != null:
		if candidate is ShipUnit:
			return candidate as ShipUnit
		candidate = candidate.get_parent()
	return null


func _determine_underwater_section(
		target_ship: ShipUnit,
		hit_position: Vector3
) -> ArmorPart.Type:
	var local_position := target_ship.to_local(hit_position)
	var hull_length := target_ship.ship_data.hull_size.z
	var section_threshold := hull_length * 0.3
	if local_position.z < -section_threshold:
		return ArmorPart.Type.BOW
	if local_position.z > section_threshold:
		return ArmorPart.Type.STERN
	return ArmorPart.Type.BELT


func _resolve_water_height() -> float:
	if get_tree() == null:
		return 0.0
	var bounds := get_tree().get_first_node_in_group(&"battlefield_bounds") \
		as BattlefieldBounds
	return bounds.get_sea_level_m() if bounds != null else 0.0


func on_spawned_from_pool() -> void:
	super.on_spawned_from_pool()
	torpedo_data = null
	speed_mps = 0.0
	travelled_distance_m = 0.0
	age_seconds = 0.0
	armed = false
	impact_processed = false
	target_ref = null
	previous_position = global_position
	desired_yaw_radians = 0.0
	launch_mode = TorpedoLaunchMode.Type.SURFACE
	launch_phase = LaunchPhase.ARMING
	intended_launch_direction = Vector3.ZERO
	airborne_age_seconds = 0.0
	_running_collision_layer = collision_layer
	_running_collision_mask = collision_mask
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gravity_scale = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	_stop_wake()


func on_recycled_to_pool() -> void:
	_stop_wake()
	torpedo_data = null
	speed_mps = 0.0
	travelled_distance_m = 0.0
	age_seconds = 0.0
	armed = false
	launch_position = Vector3.ZERO
	water_height_m = 0.0
	impact_processed = false
	target_ref = null
	previous_position = Vector3.ZERO
	desired_yaw_radians = 0.0
	launch_mode = TorpedoLaunchMode.Type.SURFACE
	launch_phase = LaunchPhase.EXPIRED
	intended_launch_direction = Vector3.ZERO
	airborne_age_seconds = 0.0
	_running_collision_layer = 0
	_running_collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	super.on_recycled_to_pool()


func _on_reset_for_pool() -> void:
	torpedo_data = null
	speed_mps = 0.0
	travelled_distance_m = 0.0
	age_seconds = 0.0
	armed = false
	launch_position = Vector3.ZERO
	water_height_m = 0.0
	impact_processed = false
	target_ref = null
	previous_position = Vector3.ZERO
	desired_yaw_radians = 0.0
	launch_mode = TorpedoLaunchMode.Type.SURFACE
	launch_phase = LaunchPhase.EXPIRED
	intended_launch_direction = Vector3.ZERO
	airborne_age_seconds = 0.0
	_running_collision_layer = 0
	_running_collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_stop_wake()


func _configure_wake() -> void:
	if wake_particles == null:
		return
	wake_particles.amount = wake_particle_count
	wake_particles.lifetime = wake_lifetime_sec
	wake_particles.local_coords = false
	wake_particles.one_shot = false
	wake_particles.fixed_fps = 30
	wake_particles.fract_delta = true
	var wake_extent := maxf(500.0, 45.0 * wake_lifetime_sec * 1.5)
	wake_particles.visibility_aabb = AABB(
		Vector3.ONE * -wake_extent,
		Vector3.ONE * wake_extent * 2.0
	)

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(
		wake_width_m * 0.28,
		0.05,
		wake_patch_length_m * 0.18
	)
	process_material.direction = Vector3.ZERO
	process_material.spread = 0.0
	process_material.initial_velocity_min = 0.0
	process_material.initial_velocity_max = 0.0
	process_material.gravity = Vector3.ZERO
	process_material.scale_min = 0.55
	process_material.scale_max = 1.35
	var fade_gradient := Gradient.new()
	fade_gradient.set_color(
		0,
		Color(wake_color.r, wake_color.g, wake_color.b, wake_color.a)
	)
	fade_gradient.set_color(
		1,
		Color(wake_color.r, wake_color.g, wake_color.b, 0.0)
	)
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade_gradient
	process_material.color_ramp = fade_texture
	wake_particles.process_material = process_material

	var wake_mesh := PlaneMesh.new()
	wake_mesh.size = Vector2(wake_width_m, wake_patch_length_m)
	var wake_material := StandardMaterial3D.new()
	wake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wake_material.vertex_color_use_as_albedo = true
	wake_material.albedo_color = Color.WHITE
	wake_material.no_depth_test = true
	wake_mesh.material = wake_material
	wake_particles.draw_pass_1 = wake_mesh


func _start_wake() -> void:
	if wake_particles == null or not wake_enabled:
		return
	wake_particles.restart()
	wake_particles.emitting = true


func _stop_wake() -> void:
	if wake_particles == null:
		return
	wake_particles.emitting = false
	wake_particles.restart()
