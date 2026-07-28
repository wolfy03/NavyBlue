extends CharacterBody3D
class_name AircraftUnit

signal destroyed(aircraft: AircraftUnit)

@onready var aircraft_mesh: MeshInstance3D = get_node_or_null(
	"MeshInstance3D"
) as MeshInstance3D
@onready var collision_shape: CollisionShape3D = get_node_or_null(
	"CollisionShape3D"
) as CollisionShape3D
@onready var movement: AircraftMovement = get_node_or_null(
	"AircraftMovement"
) as AircraftMovement
@onready var health: AircraftHealth = get_node_or_null(
	"AircraftHealth"
) as AircraftHealth
@onready var weapon_controller: AircraftWeaponController = get_node_or_null(
	"AircraftWeaponController"
) as AircraftWeaponController

var aircraft_data: AircraftData
var team: StringName = &"neutral"
var formation_offset: Vector3 = Vector3.ZERO
var active := false
var _destroyed_emitted := false


func setup(
		data: AircraftData,
		next_team: StringName,
		offset: Vector3
) -> void:
	aircraft_data = data
	team = next_team
	formation_offset = offset
	_register_groups()
	if movement != null:
		movement.setup(self, aircraft_data)
	if health != null:
		health.setup(aircraft_data)
		if not health.died.is_connected(_on_health_died):
			health.died.connect(_on_health_died)
	if weapon_controller != null:
		weapon_controller.setup(
			self,
			aircraft_data.weapon_data if aircraft_data != null else null
		)
	_apply_team_material()
	activate()
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").aircraft_spawned.emit(self)


func _physics_process(delta: float) -> void:
	if active and movement != null:
		movement.update_movement(delta)
	if active and weapon_controller != null:
		weapon_controller.update_weapon(delta)


func set_formation_target(world_position: Vector3) -> void:
	if movement != null:
		movement.set_target_position(world_position)


func activate() -> void:
	active = true
	visible = true
	set_physics_process(true)
	if collision_shape != null:
		collision_shape.disabled = false


func deactivate() -> void:
	active = false
	velocity = Vector3.ZERO
	set_physics_process(false)
	if collision_shape != null:
		collision_shape.disabled = true


func apply_damage(amount: float) -> float:
	return health.apply_damage(amount) if health != null else 0.0


func is_alive() -> bool:
	return active \
		and health != null \
		and health.is_alive() \
		and not is_queued_for_deletion()


func get_world_velocity() -> Vector3:
	return velocity


func destroy_for_cleanup() -> void:
	_on_health_died()


func _register_groups() -> void:
	add_to_group(&"aircraft")
	match team:
		&"player":
			add_to_group(&"team_player_aircraft")
		&"ally":
			add_to_group(&"team_ally_aircraft")
		&"enemy":
			add_to_group(&"team_enemy_aircraft")


func _apply_team_material() -> void:
	if aircraft_mesh == null:
		return
	var material := StandardMaterial3D.new()
	match team:
		&"player":
			material.albedo_color = Color(0.2, 0.65, 1.0)
		&"ally":
			material.albedo_color = Color(0.25, 0.85, 0.55)
		&"enemy":
			material.albedo_color = Color(1.0, 0.28, 0.2)
		_:
			material.albedo_color = Color(0.72, 0.76, 0.8)
	material.metallic = 0.18
	material.roughness = 0.62
	aircraft_mesh.material_override = material


func _on_health_died() -> void:
	if _destroyed_emitted:
		return
	_destroyed_emitted = true
	deactivate()
	destroyed.emit(self)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").aircraft_destroyed.emit(self)
	queue_free()
