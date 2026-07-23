extends "res://scripts/weapon/mount/WeaponMount.gd"
class_name TorpedoMount

@export var tube_count := 3
@export var spread_angle_degrees := 3.0
@export var yaw_speed_degrees := 10.0
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
		_turn_toward(aim_point, delta)


func can_fire_at(world_point: Vector3) -> bool:
	return super.can_fire_at(world_point) \
		and _is_inside_traverse_arc(world_point) \
		and _is_aim_aligned(world_point) \
		and not _has_friendly_in_launch_lane(world_point)


func fire() -> bool:
	if not can_fire_at(aim_point):
		return false
	var launch_count := mini(tube_count, muzzles.size())
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
	context.target = owner_ship.combat.target as Node3D \
		if owner_ship != null and owner_ship.combat != null else null
	torpedo.launch_with_context(context)
	fired.emit(torpedo)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").torpedo_fired.emit(torpedo)
	return true


func _turn_toward(world_point: Vector3, delta: float) -> void:
	var direction := world_point - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	var desired_yaw := atan2(-direction.x, -direction.z)
	global_rotation.y = rotate_toward(
		global_rotation.y,
		desired_yaw,
		deg_to_rad(yaw_speed_degrees) * delta
	)


func _is_aim_aligned(world_point: Vector3) -> bool:
	var desired_direction := world_point - global_position
	desired_direction.y = 0.0
	var mount_forward := -global_transform.basis.z
	mount_forward.y = 0.0
	if desired_direction.length_squared() < 0.01 \
			or mount_forward.length_squared() < 0.01:
		return false
	return rad_to_deg(
		mount_forward.normalized().angle_to(desired_direction.normalized())
	) <= maxf(spread_angle_degrees, 4.0)


func _has_friendly_in_launch_lane(world_point: Vector3) -> bool:
	if owner_ship == null or get_tree() == null:
		return false
	var direction := world_point - global_position
	direction.y = 0.0
	var distance := minf(direction.length(), get_range_m())
	if distance <= 0.01:
		return false
	var lane_end := global_position + direction.normalized() * distance
	var lane_width := maxf(owner_ship.get_navigation_safety_radius_m(), 60.0)
	for candidate_value in get_tree().get_nodes_in_group(&"ships"):
		var candidate := candidate_value as ShipUnit
		if candidate == null or candidate == owner_ship \
				or not candidate.is_alive() \
				or FactionRelations.are_hostile(owner_team, candidate.team):
			continue
		if _distance_to_segment_xz(
			candidate.global_position,
			global_position,
			lane_end
		) <= lane_width + candidate.get_navigation_safety_radius_m():
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
