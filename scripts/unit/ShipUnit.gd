extends CharacterBody3D
class_name ShipUnit

const SHIP_DATABASE_SCRIPT := preload("res://scripts/data/ShipDatabase.gd")

@export var ship_id := "dd_bluewind"
@export var ship_data: Resource
@export var team: StringName = &"neutral"
@export var player_controlled := false
@export var team_color := Color(0.2, 0.55, 1.0)
@export var engine_output_change_rate := 0.55
@export var ai_engagement_range := 85.0
@export var turret_scene: PackedScene = preload("res://scenes/weapon/turret.tscn")

@onready var hull_collision: CollisionShape3D = $HullCollision
@onready var hull_mesh: MeshInstance3D = $HullMesh
@onready var bow_mesh: MeshInstance3D = $BowMesh
@onready var deck_mesh: MeshInstance3D = $DeckMesh
@onready var turret_mounts: Node3D = $TurretMounts

var engine_output := 0.0
var rudder_input := 0.0
var desired_aim_point := Vector3.ZERO
var has_desired_aim_point := false
var ai_target
var turrets: Array = []

var _player_throttle_axis := 0.0
var _player_rudder_axis := 0.0
var _player_fire_pressed := false

func setup(data: Resource, team_name: StringName, is_player: bool, color: Color) -> void:
	ship_data = data
	ship_id = ship_data.id
	team = team_name
	player_controlled = is_player
	team_color = color
	name = "%s_%s" % [ship_data.id, String(team)]
	_register_groups()

func _ready() -> void:
	if ship_data == null:
		ship_data = SHIP_DATABASE_SCRIPT.new().get_ship(ship_id)
	_register_groups()
	_apply_data_to_asset()

func _physics_process(delta: float) -> void:
	if player_controlled:
		_update_player_commands(delta)
	else:
		_update_ai(delta)

	_apply_movement(delta)
	_update_turrets()

func set_player_commands(throttle_axis: float, rudder_axis: float, fire_pressed: bool) -> void:
	_player_throttle_axis = clampf(throttle_axis, -1.0, 1.0)
	_player_rudder_axis = clampf(rudder_axis, -1.0, 1.0)
	_player_fire_pressed = fire_pressed

func set_aim_point(world_point: Vector3) -> void:
	desired_aim_point = world_point
	has_desired_aim_point = true

func adjust_turret_pitch(delta_degrees: float) -> void:
	for turret in turrets:
		turret.adjust_pitch(delta_degrees)

func fire_turrets() -> void:
	for turret in turrets:
		turret.fire()

func get_speed_knots_style() -> float:
	return velocity.length()

func get_primary_impact_point(gravity: float) -> Variant:
	if turrets.is_empty():
		return null
	var turret = turrets[0]
	var origin: Vector3 = turret.get_muzzle_position()
	var velocity_vector: Vector3 = turret.get_muzzle_velocity_vector()
	var a := -0.5 * gravity
	var b := velocity_vector.y
	var c := origin.y
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return null
	var sqrt_discriminant := sqrt(discriminant)
	var t1 := (-b + sqrt_discriminant) / (2.0 * a)
	var t2 := (-b - sqrt_discriminant) / (2.0 * a)
	var t := maxf(t1, t2)
	if t <= 0.0:
		return null
	var point := origin + velocity_vector * t + Vector3(0.0, -0.5 * gravity * t * t, 0.0)
	point.y = 0.035
	return point

func _register_groups() -> void:
	add_to_group("ships")
	add_to_group("team_%s" % String(team))

func _update_player_commands(delta: float) -> void:
	engine_output = clampf(engine_output + _player_throttle_axis * engine_output_change_rate * delta, -1.0, 1.0)
	rudder_input = _player_rudder_axis
	if _player_fire_pressed:
		fire_turrets()

func _update_ai(delta: float) -> void:
	if not is_instance_valid(ai_target):
		engine_output = move_toward(engine_output, 0.35, ship_data.engine_response * delta)
		rudder_input = sin(Time.get_ticks_msec() * 0.0006 + float(get_instance_id() % 7)) * 0.35
		return

	var to_target: Vector3 = ai_target.global_position - global_position
	var distance: float = to_target.length()
	var desired_speed: float = 0.78 if distance > ai_engagement_range * 0.55 else 0.28
	engine_output = move_toward(engine_output, desired_speed, ship_data.engine_response * delta)
	_turn_toward_direction(to_target)
	set_aim_point(ai_target.global_position)
	if distance <= ai_engagement_range:
		fire_turrets()

func _apply_movement(delta: float) -> void:
	var speed_limit: float = ship_data.max_forward_speed if engine_output >= 0.0 else ship_data.max_reverse_speed
	var forward: Vector3 = -global_transform.basis.z.normalized()
	velocity = forward * engine_output * speed_limit
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0

	var speed_factor: float = maxf(absf(engine_output), 0.12)
	var reverse_factor: float = -1.0 if engine_output < 0.0 else 1.0
	rotate_y(rudder_input * deg_to_rad(ship_data.turn_rate_degrees) * speed_factor * reverse_factor * delta)

func _turn_toward_direction(world_direction: Vector3) -> void:
	world_direction.y = 0.0
	if world_direction.length_squared() < 0.01:
		rudder_input = 0.0
		return
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var signed_angle: float = forward.signed_angle_to(world_direction.normalized(), Vector3.UP)
	rudder_input = clampf(signed_angle / deg_to_rad(35.0), -1.0, 1.0)

func _update_turrets() -> void:
	if not has_desired_aim_point and player_controlled:
		set_aim_point(global_position + -global_transform.basis.z * 60.0)
	for turret in turrets:
		if has_desired_aim_point:
			turret.aim_at(desired_aim_point)

func _apply_data_to_asset() -> void:
	_apply_hull_shape()
	_apply_materials()
	_rebuild_turrets()

func _apply_hull_shape() -> void:
	var hull_size: Vector3 = ship_data.hull_size

	if hull_collision.shape:
		hull_collision.shape = hull_collision.shape.duplicate()
	if hull_mesh.mesh:
		hull_mesh.mesh = hull_mesh.mesh.duplicate()
	if bow_mesh.mesh:
		bow_mesh.mesh = bow_mesh.mesh.duplicate()
	if deck_mesh.mesh:
		deck_mesh.mesh = deck_mesh.mesh.duplicate()

	var box := hull_collision.shape as BoxShape3D
	if box:
		box.size = hull_size
	hull_collision.position.y = hull_size.y * 0.5

	var hull_box := hull_mesh.mesh as BoxMesh
	if hull_box:
		hull_box.size = hull_size
	hull_mesh.position.y = hull_size.y * 0.5

	var bow_prism := bow_mesh.mesh as PrismMesh
	if bow_prism:
		bow_prism.size = Vector3(hull_size.x, hull_size.y * 0.9, hull_size.x * 1.1)
	bow_mesh.position = Vector3(0.0, hull_size.y * 0.5, -hull_size.z * 0.55)

	var deck_box := deck_mesh.mesh as BoxMesh
	if deck_box:
		deck_box.size = Vector3(hull_size.x * 0.72, 0.22, hull_size.z * 0.52)
	deck_mesh.position = Vector3(0.0, hull_size.y + 0.12, 0.12)

func _apply_materials() -> void:
	hull_mesh.material_override = _make_material(team_color)
	bow_mesh.material_override = hull_mesh.material_override
	deck_mesh.material_override = _make_material(team_color.darkened(0.25))

func _rebuild_turrets() -> void:
	for child in turret_mounts.get_children():
		child.queue_free()
	turrets.clear()

	var start_z: float = -ship_data.turret_spacing * float(ship_data.turret_count - 1) * 0.5
	for index in range(ship_data.turret_count):
		var turret = turret_scene.instantiate()
		turret.name = "Turret_%02d" % index
		turret.position = Vector3(0.0, ship_data.hull_size.y + 0.28, start_z + ship_data.turret_spacing * index)
		turret_mounts.add_child(turret)
		turret.setup(team, team_color, ship_data.shell_muzzle_velocity, ship_data.reload_seconds)
		turrets.append(turret)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.metallic = 0.08
	return material

