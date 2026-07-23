extends "res://scripts/weapon/mount/WeaponMount.gd"
class_name CannonMount

@export var projectile_scene: PackedScene = preload("res://scenes/weapon/projectile.tscn")
@export var shell_stats: ShellStats = preload("res://scripts/combat/default_ap_shell.tres")
@export var yaw_speed := 7.5
@export var min_pitch_degrees := 1.0
@export var max_pitch_degrees := 55.0
@export var pitch_degrees := 18.0
@export var automatic_ballistic_pitch := true
@export var pitch_speed_deg_sec := 12.0
@export_range(-10.0, 10.0, 0.5) var manual_pitch_offset_deg := 0.0
@export var muzzle_velocity := 36.0
@export var reload_seconds := 1.2

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


func _ready() -> void:
	barrel_pivot.rotation.x = deg_to_rad(pitch_degrees)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if has_aim_point:
		_turn_toward(aim_point, delta)
	barrel_pivot.rotation.x = deg_to_rad(pitch_degrees)


func can_fire_at(world_point: Vector3) -> bool:
	return super.can_fire_at(world_point) and _is_inside_traverse_arc(world_point)


func adjust_pitch(delta_degrees: float) -> void:
	manual_pitch_offset_deg = clampf(
		manual_pitch_offset_deg + delta_degrees,
		-10.0,
		10.0
	)


func fire() -> bool:
	if muzzle == null or not can_fire_at(aim_point):
		return false
	var projectile := _spawn_projectile(_get_projectile_scene())
	if projectile == null:
		push_warning("Cannon mount could not create its shell projectile.")
		return false
	projectile.global_transform = muzzle.global_transform
	var active_data := weapon_data.projectile_data if weapon_data != null else null
	if projectile.has_method(&"setup_projectile_data"):
		projectile.call(&"setup_projectile_data", active_data)
	var context := ProjectileLaunchContext.new()
	context.source_ship = owner_ship
	context.source_team = owner_team
	context.source_weapon_id = StringName(weapon_data.id) if weapon_data != null else StringName()
	context.initial_transform = muzzle.global_transform
	context.initial_velocity = get_muzzle_velocity_vector()
	context.aim_point = aim_point
	if projectile.has_method(&"launch_with_context"):
		projectile.call(&"launch_with_context", context)
	elif projectile.has_method(&"launch"):
		projectile.call(
			&"launch",
			context.initial_velocity,
			context.source_team,
			shell_stats,
			context.source_ship,
			context.source_weapon_id
		)
	else:
		push_warning("Shell projectile does not implement a launch method.")
		if projectile.has_method(&"despawn"):
			projectile.call(&"despawn")
		else:
			projectile.queue_free()
		return false
	reload_left = get_reload_seconds()
	fired.emit(projectile)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").projectile_fired.emit(projectile)
	return true


func get_muzzle_velocity_vector() -> Vector3:
	if muzzle == null:
		return Vector3.ZERO
	return -muzzle.global_transform.basis.z.normalized() * muzzle_velocity


func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle != null else global_position


func _get_projectile_scene() -> PackedScene:
	if weapon_data != null and weapon_data.projectile_scene != null:
		return weapon_data.projectile_scene
	return projectile_scene


func _turn_toward(world_point: Vector3, delta: float) -> void:
	var flat_direction := world_point - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() < 0.01:
		return
	var desired_yaw := atan2(-flat_direction.x, -flat_direction.z)
	global_rotation.y = rotate_toward(
		global_rotation.y,
		desired_yaw,
		deg_to_rad(yaw_speed) * delta
	)
	if automatic_ballistic_pitch:
		var ballistic_pitch: Variant = _calculate_ballistic_pitch_deg(world_point)
		if ballistic_pitch != null:
			var desired_pitch := clampf(
				float(ballistic_pitch) + manual_pitch_offset_deg,
				min_pitch_degrees,
				max_pitch_degrees
			)
			pitch_degrees = move_toward(
				pitch_degrees,
				desired_pitch,
				pitch_speed_deg_sec * delta
			)


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
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var speed_squared := muzzle_velocity * muzzle_velocity
	var vertical_offset := world_point.y - muzzle_position.y
	var discriminant := speed_squared * speed_squared - gravity * (
		gravity * horizontal_distance * horizontal_distance
		+ 2.0 * vertical_offset * speed_squared
	)
	if discriminant < 0.0:
		return null
	var tangent := (speed_squared - sqrt(discriminant)) \
		/ (gravity * horizontal_distance)
	return rad_to_deg(atan(tangent))


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
