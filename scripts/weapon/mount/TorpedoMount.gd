extends "res://scripts/weapon/mount/WeaponMount.gd"
class_name TorpedoMount

@export var tube_count := 3
@export var spread_angle_degrees := 3.0
@export var yaw_speed_degrees := 10.0
@export var friendly_lane_half_width_m := 15.0
@export var friendly_lane_safety_margin_m := 10.0
@export var muzzle_paths: Array[NodePath] = [
	NodePath("Muzzles/Muzzle0"),
	NodePath("Muzzles/Muzzle1"),
	NodePath("Muzzles/Muzzle2"),
]

var muzzles: Array[Node3D] = []


func _ready() -> void:
	for path in muzzle_paths:
		var muzzle := get_node_or_null(path) as Node3D
		if muzzle != null:
			muzzles.append(muzzle)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if has_aim_point:
		update_traverse_toward(
			aim_point,
			get_modified_traverse_speed(yaw_speed_degrees),
			delta
		)


func get_fire_readiness_at(
		world_point: Vector3
) -> WeaponFireReadiness.State:
	var readiness := super.get_fire_readiness_at(world_point)
	if readiness != WeaponFireReadiness.State.READY:
		return readiness
	if muzzles.is_empty():
		return WeaponFireReadiness.State.NO_MUZZLE
	if get_salvo_projectile_count() <= 0:
		return WeaponFireReadiness.State.NO_AMMUNITION
	if not _is_aim_aligned(
		world_point,
		maxf(spread_angle_degrees, 4.0)
	):
		return WeaponFireReadiness.State.NOT_ALIGNED
	if _has_friendly_in_launch_lane(world_point):
		return WeaponFireReadiness.State.FRIENDLY_BLOCKED
	return WeaponFireReadiness.State.READY


func fire() -> bool:
	if not can_fire_at(aim_point):
		return false
	var launch_count := get_salvo_projectile_count()
	var launched := 0
	for index in launch_count:
		if _launch_torpedo(index, launch_count):
			launched += 1
	if launched <= 0:
		return false
	reload_left = get_reload_seconds()
	return true


func _launch_torpedo(index: int, total_count: int) -> bool:
	if weapon_data == null or weapon_data.projectile_scene == null:
		return false
	var torpedo := _spawn_projectile(weapon_data.projectile_scene) \
		as TorpedoProjectile
	if torpedo == null:
		push_warning("Torpedo projectile scene must instantiate TorpedoProjectile.")
		return false
	var muzzle := muzzles[index]
	var launch_transform := muzzle.global_transform
	var center_offset := float(total_count - 1) * 0.5
	var spread_offset := (float(index) - center_offset) * spread_angle_degrees
	launch_transform.basis = launch_transform.basis.rotated(
		Vector3.UP,
		deg_to_rad(spread_offset)
	)
	torpedo.global_transform = launch_transform
	torpedo.setup_projectile_data(
		weapon_data.projectile_data as TorpedoProjectileData
	)
	var context := ProjectileLaunchContext.new()
	context.source_ship = owner_ship
	context.source_team = owner_team
	context.source_weapon_id = StringName(weapon_data.id)
	context.initial_transform = launch_transform
	context.aim_point = aim_point
	context.runtime_stats = runtime_stats.duplicate_stats()
	context.target = owner_ship.combat.target as Node3D \
		if owner_ship != null and owner_ship.combat != null else null
	torpedo.launch_with_context(context)
	fired.emit(torpedo)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").torpedo_fired.emit(torpedo)
	return true


func get_projectile_damage() -> float:
	var data := weapon_data.projectile_data as TorpedoProjectileData \
		if weapon_data != null else null
	if data == null:
		return super.get_projectile_damage()
	return (
		maxf(data.direct_damage, 0.0)
		+ maxf(data.explosion_damage, 0.0)
	) * maxf(runtime_stats.damage_multiplier, 0.0)


func get_distance_to_world_point(world_point: Vector3) -> float:
	return CombatGeometryXZ.distance_xz(global_position, world_point)


func get_salvo_projectile_count() -> int:
	return mini(
		muzzles.size(),
		maxi(0, tube_count + runtime_stats.projectile_count_bonus)
	)


func _has_friendly_in_launch_lane(world_point: Vector3) -> bool:
	if owner_ship == null or get_tree() == null:
		return false
	var direction := world_point - global_position
	direction.y = 0.0
	var distance := minf(direction.length(), get_range_m())
	var torpedo_data := weapon_data.projectile_data as TorpedoProjectileData \
		if weapon_data != null else null
	if torpedo_data != null and torpedo_data.maximum_range_m > 0.0:
		distance = minf(
			distance,
			torpedo_data.maximum_range_m * maxf(
				runtime_stats.range_multiplier,
				0.0
			)
		)
	if distance <= 0.01:
		return false
	var lane_end := global_position + direction.normalized() * distance
	for candidate_value in get_tree().get_nodes_in_group(&"ships"):
		var candidate := candidate_value as ShipUnit
		if candidate == null or candidate == owner_ship \
				or candidate.is_queued_for_deletion() \
				or not candidate.is_inside_tree() \
				or not candidate.is_alive() \
				or FactionRelations.are_hostile(owner_team, candidate.team):
			continue
		var candidate_half_width := candidate.ship_data.hull_size.x * 0.5 \
			if candidate.ship_data != null else 5.0
		var blocked_distance := friendly_lane_half_width_m \
			+ candidate_half_width \
			+ friendly_lane_safety_margin_m
		if _distance_to_segment_xz(
			candidate.global_position,
			global_position,
			lane_end
		) <= blocked_distance:
			return true
	return false


func _distance_to_segment_xz(
		point: Vector3,
		start: Vector3,
		end: Vector3
) -> float:
	var point_2d := Vector2(point.x, point.z)
	var start_2d := Vector2(start.x, start.z)
	var end_2d := Vector2(end.x, end.z)
	var segment := end_2d - start_2d
	if segment.length_squared() <= 0.001:
		return point_2d.distance_to(start_2d)
	var ratio := clampf(
		(point_2d - start_2d).dot(segment) / segment.length_squared(),
		0.0,
		1.0
	)
	return point_2d.distance_to(start_2d + segment * ratio)
