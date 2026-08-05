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
@onready var fighter_combat_controller: FighterCombatController = \
	get_node_or_null("FighterCombatController") as FighterCombatController
@onready var payload_hardpoint: Marker3D = get_node_or_null(
	"PayloadHardpoint"
) as Marker3D
## Visual model layer: the ONLY node banking is ever applied to. Cached once;
## the physics root, collision shape and weapon transforms never roll.
@onready var visual_model: Node3D = get_node_or_null(
	"AircraftVisualSample"
) as Node3D

var aircraft_data: AircraftData
var team: StringName = &"neutral"
var formation_offset: Vector3 = Vector3.ZERO
var active := false
var weapon_updates_managed_by_squadron := false
var _destroyed_emitted := false
var battle_services: BattleServices

var _default_bank_settings: AircraftBankVisualSettings
var _previous_horizontal_velocity := Vector3.ZERO
var _current_bank_angle_rad := 0.0


func setup(
		data: AircraftData,
		next_team: StringName,
		offset: Vector3,
		next_battle_services: BattleServices = null
) -> void:
	aircraft_data = data
	team = next_team
	formation_offset = offset
	battle_services = next_battle_services
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
			aircraft_data.weapon_data if aircraft_data != null else null,
			battle_services
		)
	if fighter_combat_controller != null:
		fighter_combat_controller.setup(self)
	_apply_team_material()
	activate()
	if battle_services != null:
		battle_services.events.emit_aircraft_spawned(self)


func _physics_process(delta: float) -> void:
	if active and movement != null:
		movement.update_movement(delta)
	if active:
		update_visual_bank(delta)
	if active and weapon_controller != null \
			and not weapon_updates_managed_by_squadron:
		weapon_controller.update_weapon(delta)


## Rolls the visual model into horizontal turns. Reads only this aircraft's
## own velocity; writes only the visual child's absolute rotation.z, so the
## physics root, collision and weapon transforms are untouched.
func update_visual_bank(delta: float) -> void:
	if visual_model == null or delta <= 0.0:
		return
	var settings := _get_bank_settings()
	var horizontal_velocity := velocity
	horizontal_velocity.y = 0.0
	var target_bank_rad := 0.0
	var minimum_speed := maxf(settings.minimum_horizontal_speed_mps, 0.0)
	if horizontal_velocity.length() >= minimum_speed \
			and _previous_horizontal_velocity.length() >= minimum_speed:
		# Turn direction and rate from the signed change of the aircraft's own
		# horizontal track. Flying straight (or diving without turning) gives
		# zero rate, so the model levels out on its own.
		var turn_rate_rad := _previous_horizontal_velocity.signed_angle_to(
			horizontal_velocity,
			Vector3.UP
		) / delta
		var full_bank_rate_rad := deg_to_rad(maxf(
			settings.turn_rate_for_full_bank_deg_sec,
			0.001
		))
		var maximum_bank_rad := deg_to_rad(clampf(
			settings.maximum_bank_angle_degrees,
			0.0,
			85.0
		))
		# Left turn (positive yaw about UP) banks left, which is a positive
		# roll about +Z for a -Z-forward model.
		target_bank_rad = clampf(
			turn_rate_rad / full_bank_rate_rad,
			-1.0,
			1.0
		) * maximum_bank_rad
	_previous_horizontal_velocity = horizontal_velocity
	var bank_speed_deg := settings.bank_response_speed_deg_sec \
		if absf(target_bank_rad) > absf(_current_bank_angle_rad) \
		else settings.bank_return_speed_deg_sec
	_current_bank_angle_rad = move_toward(
		_current_bank_angle_rad,
		target_bank_rad,
		deg_to_rad(maxf(bank_speed_deg, 0.0)) * delta
	)
	# Absolute assignment: never accumulated with rotate_z, so the model can
	# never wind up or drift.
	visual_model.rotation.z = _current_bank_angle_rad


func _get_bank_settings() -> AircraftBankVisualSettings:
	if aircraft_data != null and aircraft_data.bank_visual_settings != null:
		return aircraft_data.bank_visual_settings
	if _default_bank_settings == null:
		_default_bank_settings = AircraftBankVisualSettings.new()
	return _default_bank_settings


func set_weapon_updates_managed_by_squadron(managed: bool) -> void:
	weapon_updates_managed_by_squadron = managed


func set_formation_target(world_position: Vector3) -> void:
	if movement != null:
		movement.set_target_position(world_position)


func set_direct_flight(
		direction: Vector3,
		speed_mps: float
) -> void:
	if movement != null:
		movement.set_direct_flight(direction, speed_mps)


func set_formation_flight() -> void:
	if movement != null:
		movement.set_formation_mode()


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


func apply_damage(
		amount: float,
		info: AircraftDamageInfo = null
) -> float:
	return health.apply_damage(amount, info) if health != null else 0.0


func is_alive() -> bool:
	return active \
		and health != null \
		and health.is_alive() \
		and not is_queued_for_deletion()


func get_world_velocity() -> Vector3:
	return velocity


func get_forward_direction() -> Vector3:
	var forward := -global_transform.basis.z
	return forward.normalized() \
		if forward.length_squared() > 0.0001 else Vector3.FORWARD


func get_payload_release_transform() -> Transform3D:
	return payload_hardpoint.global_transform \
		if payload_hardpoint != null else global_transform


func get_fighter_combat_data() -> FighterCombatData:
	return aircraft_data.fighter_combat_data \
		if aircraft_data != null else null


func get_aircraft_role() -> AircraftData.AircraftRole:
	return aircraft_data.role \
		if aircraft_data != null \
		else AircraftData.AircraftRole.RECON


func get_team() -> StringName:
	return team


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
	material.albedo_color = battle_services.get_faction_color(
		team,
		Color(0.72, 0.76, 0.8)
	) if battle_services != null else Color(0.72, 0.76, 0.8)
	material.metallic = 0.18
	material.roughness = 0.62
	aircraft_mesh.material_override = material


func _on_health_died() -> void:
	if _destroyed_emitted:
		return
	_destroyed_emitted = true
	if fighter_combat_controller != null:
		fighter_combat_controller.disable_combat()
	deactivate()
	destroyed.emit(self)
	if battle_services != null:
		battle_services.events.emit_aircraft_destroyed(self)
	queue_free()
