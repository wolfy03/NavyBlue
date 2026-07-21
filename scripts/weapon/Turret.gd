extends Node3D
class_name Turret

@export var projectile_scene: PackedScene = preload("res://scenes/weapon/projectile.tscn")
@export var shell_stats: ShellStats = preload("res://scripts/combat/default_ap_shell.tres")
@export var yaw_speed := 7.5
@export var min_pitch_degrees := 4.0
@export var max_pitch_degrees := 55.0
@export var pitch_degrees := 18.0
@export var muzzle_velocity := 36.0
@export var reload_seconds := 1.2

@onready var base_mesh: MeshInstance3D = $Base
@onready var barrel_pivot: Node3D = $BarrelPivot
@onready var barrel_mesh: MeshInstance3D = $BarrelPivot/Barrel
@onready var muzzle: Node3D = $BarrelPivot/Muzzle

var owner_team: StringName = &"neutral"
var aim_point := Vector3.ZERO
var has_aim_point := false
var reload_left := 0.0

func setup(team: StringName, team_color: Color, velocity: float, reload_time: float) -> void:
	owner_team = team
	muzzle_velocity = velocity
	reload_seconds = reload_time
	_apply_team_materials(team_color)

func _ready() -> void:
	barrel_pivot.rotation.x = deg_to_rad(pitch_degrees)

func _physics_process(delta: float) -> void:
	reload_left = maxf(0.0, reload_left - delta)
	if has_aim_point:
		_turn_toward(aim_point, delta)
	barrel_pivot.rotation.x = deg_to_rad(pitch_degrees)

func aim_at(world_point: Vector3) -> void:
	aim_point = world_point
	has_aim_point = true

func adjust_pitch(delta_degrees: float) -> void:
	pitch_degrees = clampf(pitch_degrees + delta_degrees, min_pitch_degrees, max_pitch_degrees)

func fire() -> bool:
	if reload_left > 0.0 or muzzle == null:
		return false

	var projectile := projectile_scene.instantiate() as Projectile
	if projectile == null:
		push_warning("Turret projectile scene must instantiate Projectile.")
		return false
	var projectile_parent := get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_tree().root
	projectile_parent.add_child(projectile)
	projectile.global_transform = muzzle.global_transform
	projectile.launch(get_muzzle_velocity_vector(), owner_team, shell_stats)
	reload_left = reload_seconds
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").projectile_fired.emit(projectile)
	return true

func get_muzzle_velocity_vector() -> Vector3:
	return -muzzle.global_transform.basis.z.normalized() * muzzle_velocity

func get_muzzle_position() -> Vector3:
	return muzzle.global_position

func _turn_toward(world_point: Vector3, delta: float) -> void:
	var flat_direction := world_point - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() < 0.01:
		return
	var desired_yaw := atan2(-flat_direction.x, -flat_direction.z)
	global_rotation.y = lerp_angle(global_rotation.y, desired_yaw, clampf(yaw_speed * delta, 0.0, 1.0))

func _apply_team_materials(team_color: Color) -> void:
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = team_color.lightened(0.12)
	base_material.roughness = 0.72
	base_mesh.material_override = base_material

	var barrel_material := StandardMaterial3D.new()
	barrel_material.albedo_color = Color(0.12, 0.14, 0.16)
	barrel_material.roughness = 0.85
	barrel_mesh.material_override = barrel_material
