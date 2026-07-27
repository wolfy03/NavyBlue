extends "res://scripts/weapon/mount/WeaponMount.gd"
class_name CannonMount

static var _warned_unreachable_range_ids: Dictionary = {}

@export var projectile_scene: PackedScene = preload("res://scenes/weapon/projectile.tscn")
@export var shell_stats: ShellStats = preload("res://scripts/combat/default_ap_shell.tres")
@export var yaw_speed := 7.5
@export var min_pitch_degrees := 1.0
@export var max_pitch_degrees := 55.0
@export var pitch_degrees := 18.0
@export var automatic_ballistic_pitch := true
@export var pitch_speed_deg_sec := 12.0
@export var pitch_alignment_tolerance_degrees := 0.5
@export_range(-10.0, 10.0, 0.5) var manual_pitch_offset_deg := 0.0
@export var muzzle_velocity := 36.0
@export var reload_seconds := 1.2
@export var bonus_projectile_spread_degrees := 0.6
@export_range(1.0, 1.05, 0.001) var physical_range_tolerance_ratio := 1.005

@onready var base_mesh: MeshInstance3D = $Base
@onready var barrel_pivot: Node3D = $BarrelPivot
@onready var barrel_mesh: MeshInstance3D = $BarrelPivot/Barrel
@onready var muzzle: Node3D = $BarrelPivot/Muzzle


func setup(
		data: WeaponData,
		slot: ShipWeaponSlotData,
		ship: ShipUnit,
		team: StringName
) -> void:
	super.setup(data, slot, ship, team)
	if weapon_data != null:
		reload_seconds = weapon_data.reload_seconds
		muzzle_velocity = weapon_data.muzzle_velocity
		yaw_speed = weapon_data.turret_turn_speed_degrees
		max_pitch_degrees = weapon_data.max_pitch_degrees
		if weapon_data.projectile_scene != null:
			projectile_scene = weapon_data.projectile_scene
	if slot_data != null:
		min_pitch_degrees = slot_data.elevation_min_degrees
		max_pitch_degrees = minf(max_pitch_degrees, slot_data.elevation_max_degrees)
	var team_color := ship.team_color if ship != null else Color.WHITE
	_apply_team_materials(team_color)
	if weapon_data != null \
			and not is_configured_range_physically_reachable() \
			and not weapon_data.id.is_empty() \
			and not _warned_unreachable_range_ids.has(weapon_data.id):
		_warned_unreachable_range_ids[weapon_data.id] = true
		push_warning(
			"Configured cannon range exceeds the physical ballistic limit: %s"
			% weapon_data.id
		)


func _ready() -> void:
	barrel_pivot.rotation.x = deg_to_rad(pitch_degrees)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if has_aim_point:
		_turn_toward(aim_point, delta)
	barrel_pivot.rotation.x = deg_to_rad(pitch_degrees)


func get_fire_readiness_at(
		world_point: Vector3
) -> WeaponFireReadiness.State:
	var readiness := super.get_fire_readiness_at(world_point)
	if readiness != WeaponFireReadiness.State.READY:
		return readiness
	if muzzle == null:
		return WeaponFireReadiness.State.NO_MUZZLE
	if not _is_aim_aligned(world_point, 3.0):
		return WeaponFireReadiness.State.NOT_ALIGNED
	var required_pitch: Variant = _calculate_ballistic_pitch_deg(world_point)
	if required_pitch == null:
		return WeaponFireReadiness.State.NO_BALLISTIC_SOLUTION
	var desired_pitch := float(required_pitch) + manual_pitch_offset_deg
	if desired_pitch < min_pitch_degrees or desired_pitch > max_pitch_degrees:
		return WeaponFireReadiness.State.NO_BALLISTIC_SOLUTION
	if absf(pitch_degrees - desired_pitch) \
			> pitch_alignment_tolerance_degrees:
		return WeaponFireReadiness.State.NOT_ELEVATION_ALIGNED
	return WeaponFireReadiness.State.READY


func adjust_pitch(delta_degrees: float) -> void:
	manual_pitch_offset_deg = clampf(
		manual_pitch_offset_deg + delta_degrees,
		-10.0,
		10.0
	)


func fire() -> bool:
	if muzzle == null or not can_fire_at(aim_point):
		return false
	var launched := 0
	var launch_count := get_salvo_projectile_count()
	for index in range(launch_count):
		if _launch_shell(index, launch_count):
			launched += 1
	if launched <= 0:
		return false
	reload_left = get_reload_seconds()
	return true


func _launch_shell(index: int, total_count: int) -> bool:
	var projectile := _spawn_projectile(_get_projectile_scene())
	if projectile == null:
		push_warning("Cannon mount could not create its shell projectile.")
		return false
	var center_offset := float(total_count - 1) * 0.5
	var spread_offset_degrees := (
		float(index) - center_offset
	) * bonus_projectile_spread_degrees
	var launch_transform := muzzle.global_transform
	launch_transform.basis = launch_transform.basis.rotated(
		Vector3.UP,
		deg_to_rad(spread_offset_degrees)
	)
	projectile.global_transform = launch_transform
	var active_data := weapon_data.projectile_data if weapon_data != null else null
	if projectile.has_method(&"setup_projectile_data"):
		projectile.call(&"setup_projectile_data", active_data)
	var context := ProjectileLaunchContext.new()
	context.source_actor = owner_ship
	context.source_team = owner_team
	context.source_weapon_id = StringName(weapon_data.id) if weapon_data != null else StringName()
	context.source_projectile_data = active_data
	context.initial_transform = launch_transform
	context.initial_velocity = -launch_transform.basis.z.normalized() \
		* get_modified_projectile_speed(muzzle_velocity)
	context.aim_point = aim_point
	context.runtime_stats = runtime_stats.duplicate_stats()
	if projectile.has_method(&"launch_with_context"):
		projectile.call(&"launch_with_context", context)
	elif projectile.has_method(&"launch"):
		projectile.call(
			&"launch",
			context.initial_velocity,
			context.source_team,
			shell_stats,
			context.source_actor,
			context.source_weapon_id
		)
	else:
		push_warning("Shell projectile does not implement a launch method.")
		if projectile.has_method(&"despawn"):
			projectile.call(&"despawn")
		else:
			projectile.queue_free()
		return false
	fired.emit(projectile)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").projectile_fired.emit(projectile)
	return true


func get_muzzle_velocity_vector() -> Vector3:
	if muzzle == null:
		return Vector3.ZERO
	return -muzzle.global_transform.basis.z.normalized() \
		* get_modified_projectile_speed(muzzle_velocity)


func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle != null else global_position


func _get_projectile_scene() -> PackedScene:
	if weapon_data != null and weapon_data.projectile_scene != null:
		return weapon_data.projectile_scene
	return projectile_scene


func _turn_toward(world_point: Vector3, delta: float) -> void:
	update_traverse_toward(
		world_point,
		get_modified_traverse_speed(yaw_speed),
		delta
	)
	if automatic_ballistic_pitch:
		var ballistic_pitch: Variant = _calculate_ballistic_pitch_deg(world_point)
		if ballistic_pitch != null:
			var desired_pitch := float(ballistic_pitch) + manual_pitch_offset_deg
			if desired_pitch < min_pitch_degrees \
					or desired_pitch > max_pitch_degrees:
				return
			pitch_degrees = move_toward(
				pitch_degrees,
				desired_pitch,
				pitch_speed_deg_sec * delta
			)


func _has_projectile_available() -> bool:
	return _get_projectile_scene() != null


func _calculate_ballistic_pitch_deg(world_point: Vector3) -> Variant:
	if muzzle == null:
		return null
	var muzzle_position := muzzle.global_position
	var horizontal_offset := Vector2(
		world_point.x - muzzle_position.x,
		world_point.z - muzzle_position.z
	)
	var horizontal_distance := horizontal_offset.length()
	if horizontal_distance < 0.01:
		return null
	var effective_muzzle_velocity := get_modified_projectile_speed(
		muzzle_velocity
	)
	var vertical_offset := world_point.y - muzzle_position.y
	var angle: Variant = BallisticMath.solve_low_arc_angle(
		horizontal_distance,
		vertical_offset,
		effective_muzzle_velocity,
		get_effective_gravity_mps2()
	)
	return rad_to_deg(float(angle)) if angle != null else null


func get_effective_gravity_mps2() -> float:
	var shell_data := weapon_data.projectile_data as ShellProjectileData \
		if weapon_data != null else null
	return BallisticMath.get_effective_gravity_mps2(shell_data)


func get_physical_maximum_range_m() -> float:
	return BallisticMath.calculate_maximum_range(
		get_modified_projectile_speed(muzzle_velocity),
		get_effective_gravity_mps2(),
		max_pitch_degrees
	)


func is_configured_range_physically_reachable() -> bool:
	var physical_maximum := get_physical_maximum_range_m()
	return physical_maximum > 0.0 \
		and get_range_m() \
			<= physical_maximum * physical_range_tolerance_ratio


func _apply_team_materials(team_color: Color) -> void:
	if base_mesh == null or barrel_mesh == null:
		return
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = team_color.lightened(0.12)
	base_material.roughness = 0.72
	base_mesh.material_override = base_material
	var barrel_material := StandardMaterial3D.new()
	barrel_material.albedo_color = Color(0.12, 0.14, 0.16)
	barrel_material.roughness = 0.85
	barrel_mesh.material_override = barrel_material
