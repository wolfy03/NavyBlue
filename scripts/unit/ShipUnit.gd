extends CharacterBody3D
class_name ShipUnit

const SHIP_DATABASE_SCRIPT := preload("res://scripts/data/ShipDatabase.gd")
const WEAPON_DATABASE_SCRIPT := preload("res://scripts/data/WeaponDatabase.gd")

@export var ship_id := "dd_bluewind"
@export var ship_data: ShipData
@export var team: StringName = &"neutral"
@export var fleet_id: StringName = &""
@export var player_controlled := false
@export var team_color := Color(0.2, 0.55, 1.0)
@export var engine_output_change_rate := 0.55
# Deprecated: compatibility only. New weapons use WeaponData.mount_scene.
@export var turret_scene: PackedScene
@export var weapon_loadout: ShipWeaponLoadout

@onready var hull_collision: CollisionShape3D = $HullCollision
@onready var hull_mesh: MeshInstance3D = $HullMesh
@onready var bow_mesh: MeshInstance3D = $BowMesh
@onready var deck_mesh: MeshInstance3D = $DeckMesh
@onready var weapon_mount_root: Node3D = $WeaponMountRoot
@onready var movement: ShipMovement = $ShipMovement
@onready var navigation: ShipNavigationController = $ShipNavigationController
@onready var avoidance: ShipAvoidanceController = $ShipAvoidanceController
@onready var combat: ShipCombat = $ShipCombat
@onready var health: ShipHealth = $ShipHealth
@onready var damage_status: ShipDamageStatus = $ShipDamageStatus
@onready var targeting: ThreatTargetingComponent = $ThreatTargetingComponent
@onready var ai: ShipAI = $ShipAI
@onready var visual_builder: Node = $ShipVisualBuilder
@onready var buoyancy: Node = $ShipBuoyancy
@onready var carrier_air_group: CarrierAirGroup = get_node_or_null(
	"CarrierAirGroup"
) as CarrierAirGroup
@onready var carrier_air_group_ai: CarrierAirGroupAI = get_node_or_null(
	"CarrierAirGroupAI"
) as CarrierAirGroupAI

var _player_throttle_axis := 0.0
var _player_rudder_axis := 0.0
var _player_cannon_fire_pressed := false
var _player_torpedo_fire_pressed := false
var _is_sinking: bool = false
var _ai_candidate_provider := Callable()
var _fleet_controller_ref: WeakRef
var _fleet_tactical_context: FleetMemberContext
var _weapon_database := WEAPON_DATABASE_SCRIPT.new()
var weapon_runtime_stats_by_slot: Dictionary = {}
var battle_services: BattleServices

func setup(
		data: ShipData,
		team_name: StringName,
		is_player: bool,
		color: Color,
		loadout: ShipWeaponLoadout = null,
		runtime_stats_data: Dictionary = {},
		next_battle_services: BattleServices = null
) -> void:
	ship_data = data
	ship_id = ship_data.id
	team = team_name
	player_controlled = is_player
	team_color = color
	battle_services = next_battle_services
	weapon_loadout = loadout.duplicate_loadout() if loadout != null else null
	set_weapon_runtime_stats_save_data(runtime_stats_data)
	name = "%s_%s" % [ship_data.id, String(team)]
	_register_groups()

func _ready() -> void:
	if ship_data == null:
		ship_data = SHIP_DATABASE_SCRIPT.new().get_ship(ship_id)
	_register_groups()
	_setup_components()

func _physics_process(delta: float) -> void:
	if not player_controlled:
		targeting.update_targeting(delta)
	navigation.update_navigation(delta)
	avoidance.update_avoidance(delta)
	if player_controlled:
		var has_manual_input := absf(_player_throttle_axis) > 0.01 or absf(_player_rudder_axis) > 0.01
		var requires_boundary_recovery := navigation.battlefield_bounds != null \
			and not navigation.battlefield_bounds.is_inside_bounds(global_position)
		if has_manual_input and not requires_boundary_recovery:
			navigation.clear_navigation_target()
			movement.set_input(_player_throttle_axis, _player_rudder_axis)
		elif navigation.has_navigation_target:
			_apply_navigation_movement()
		else:
			movement.set_input(0.0, 0.0)
			movement.apply_avoidance(avoidance.steering_offset, avoidance.speed_scale)
		if _player_cannon_fire_pressed:
			combat.fire_cannons()
		if _player_torpedo_fire_pressed:
			combat.fire_torpedoes()
	else:
		ai.update_ai(self, movement, navigation, combat, ship_data, delta)
		if navigation.has_navigation_target:
			_apply_navigation_movement()
		else:
			movement.apply_avoidance(avoidance.steering_offset, avoidance.speed_scale)

	movement.apply_movement(delta)
	navigation.constrain_owner_to_bounds()
	buoyancy.apply_buoyancy(self)
	combat.update_weapon_mounts(self, player_controlled)

func set_player_commands(
		throttle_axis: float,
		rudder_axis: float,
		cannon_fire_pressed: bool,
		torpedo_fire_pressed: bool = false
) -> void:
	_player_throttle_axis = clampf(throttle_axis, -1.0, 1.0)
	_player_rudder_axis = clampf(rudder_axis, -1.0, 1.0)
	_player_cannon_fire_pressed = cannon_fire_pressed
	_player_torpedo_fire_pressed = torpedo_fire_pressed


func suspend_player_combat_input(
		preserve_throttle: bool = true
) -> void:
	if not preserve_throttle:
		_player_throttle_axis = 0.0
	_player_rudder_axis = 0.0
	_player_cannon_fire_pressed = false
	_player_torpedo_fire_pressed = false


func set_aim_point(world_point: Vector3) -> void:
	combat.set_aim_point(world_point)


func apply_manual_aim_command(
		command: ShipManualAimCommand
) -> void:
	combat.apply_manual_aim_command(command)


func get_selected_cannon_maximum_range_m() -> float:
	return combat.get_selected_cannon_maximum_range_m() \
		if combat != null else 0.0

func set_navigation_target(world_position: Vector3) -> void:
	navigation.set_navigation_target(world_position)

func clear_navigation_target() -> void:
	navigation.clear_navigation_target()
	movement.stop()

func get_navigation_path() -> PackedVector3Array:
	return navigation.current_path

func adjust_turret_pitch(delta_degrees: float) -> void:
	combat.adjust_turret_pitch(delta_degrees)

func fire_turrets() -> void:
	# Deprecated: compatibility only. Use fire_cannons().
	fire_cannons()


func fire_cannons() -> void:
	combat.fire_cannons()


func fire_torpedoes() -> void:
	combat.fire_torpedoes()


func launch_air_squadron(
		squadron_id: String,
		world_position: Vector3
) -> AircraftSquadron:
	if carrier_air_group == null:
		return null
	return carrier_air_group.launch_squadron(squadron_id, world_position)


func recall_air_squadrons() -> void:
	if carrier_air_group != null:
		carrier_air_group.request_all_squadrons_return()


func launch_air_strike(
		squadron_id: String,
		target_ship: Node3D,
		mission_data: AirMissionData = null
) -> AircraftSquadron:
	if carrier_air_group == null:
		return null
	return carrier_air_group.launch_strike_squadron(
		squadron_id,
		target_ship,
		mission_data
	)


func debug_launch_first_squadron(
		world_position: Vector3
) -> AircraftSquadron:
	if carrier_air_group == null:
		return null
	return carrier_air_group.debug_launch_first_squadron(world_position)


func debug_recall_all_squadrons() -> void:
	recall_air_squadrons()


func restore_run_state(data: Dictionary) -> void:
	if health != null:
		var saved_maximum := maxf(
			float(data.get("maximum_hp", health.max_health)),
			1.0
		)
		var saved_current := float(data.get(
			"current_hp",
			saved_maximum * float(data.get("hp_ratio", 1.0))
		))
		health.current_health = clampf(
			saved_current,
			0.0,
			health.max_health
		)
	if movement != null:
		var saved_output := clampf(
			float(data.get("engine_output", 0.0)),
			-1.0,
			1.0
		)
		movement.engine_output = saved_output
		movement.set_movement_command(saved_output, 0.0)
	var damage_value: Variant = data.get("damage_status", {})
	if damage_status != null and damage_value is Dictionary:
		damage_status.restore_from_save_data(damage_value)


func resolve_battle_end(success: bool) -> void:
	if carrier_air_group != null:
		carrier_air_group.resolve_battle_end(success)


func equip_weapon(
	slot_id: StringName,
	weapon_id: String
) -> WeaponMountValidationResult:
	var slot := _find_weapon_slot(slot_id)
	var weapon_data := _weapon_database.find_weapon(weapon_id)
	var validation := WeaponMountValidator.validate(slot, weapon_data)
	if not validation.valid:
		return validation
	if weapon_loadout == null:
		weapon_loadout = ShipWeaponLoadout.from_ship_data(ship_data)
	weapon_loadout.set_weapon_id(slot_id, weapon_id)
	if is_node_ready():
		_rebuild_weapon_mounts()
	return validation


func get_weapon_loadout_save_data() -> Dictionary:
	return weapon_loadout.to_dictionary() if weapon_loadout != null else {}


func get_weapon_runtime_stats(slot_id: StringName) -> WeaponRuntimeStats:
	var key := String(slot_id)
	var existing: Variant = weapon_runtime_stats_by_slot.get(key)
	if existing is WeaponRuntimeStats:
		return existing as WeaponRuntimeStats
	var stats := WeaponRuntimeStats.new()
	weapon_runtime_stats_by_slot[key] = stats
	return stats


func set_weapon_runtime_stats(
		slot_id: StringName,
		stats: WeaponRuntimeStats
) -> void:
	if slot_id.is_empty():
		return
	weapon_runtime_stats_by_slot[String(slot_id)] = stats.duplicate_stats() \
		if stats != null else WeaponRuntimeStats.new()
	if is_node_ready():
		for mount in combat.weapon_mounts:
			if is_instance_valid(mount) and mount.slot_data != null \
					and mount.slot_data.slot_id == slot_id:
				mount.set_runtime_stats(
					weapon_runtime_stats_by_slot[String(slot_id)]
				)


func get_weapon_runtime_stats_save_data() -> Dictionary:
	_capture_runtime_stats_from_mounts()
	var serialized: Dictionary = {}
	var slot_ids: Array = weapon_runtime_stats_by_slot.keys()
	slot_ids.sort()
	for slot_id_value in slot_ids:
		var stats := weapon_runtime_stats_by_slot[slot_id_value] \
			as WeaponRuntimeStats
		if stats != null:
			serialized[str(slot_id_value)] = stats.to_dictionary()
	return serialized


func set_weapon_runtime_stats_save_data(data: Dictionary) -> void:
	weapon_runtime_stats_by_slot.clear()
	for slot_id_value in data:
		var stats_value: Variant = data[slot_id_value]
		if stats_value is Dictionary:
			weapon_runtime_stats_by_slot[str(slot_id_value)] = \
				WeaponRuntimeStats.from_dictionary(stats_value)
	if is_node_ready():
		_apply_runtime_stats_to_mounts(combat.weapon_mounts)

func set_ai_target(target) -> void:
	targeting.force_target(target)


func configure_ai_target_provider(provider: Callable) -> void:
	_ai_candidate_provider = provider
	if targeting != null:
		targeting.set_candidate_provider(provider)


func get_ai_target():
	return targeting.get_current_target()


func get_ai_debug_data() -> Dictionary:
	var result := targeting.get_debug_snapshot()
	result.merge(ai.get_debug_data(), true)
	result["navigation_path_calculation_count"] = navigation.path_calculation_count
	result["fleet_id"] = fleet_id
	result["tactical_role"] = _fleet_tactical_context.get_role_name() \
		if _fleet_tactical_context != null else &"none"
	result["tactical_position"] = _fleet_tactical_context.tactical_position \
		if _fleet_tactical_context != null else Vector3.ZERO
	result["tactical_heading"] = _fleet_tactical_context.tactical_heading \
		if _fleet_tactical_context != null else Vector3.FORWARD
	result["tactical_position_was_clamped"] = _fleet_tactical_context.tactical_position_was_clamped \
		if _fleet_tactical_context != null else false
	return result


func set_ai_debug_enabled(enabled: bool) -> void:
	targeting.debug_enabled = enabled


func set_fleet_controller(controller: FleetAIController) -> void:
	_fleet_controller_ref = weakref(controller) if controller != null else null
	if controller != null:
		targeting.set_assignment_tracker(controller.assignment_tracker)
	else:
		targeting.set_assignment_tracker(FleetTargetAssignmentTracker.new())
	targeting.set_fleet_controller(controller)
	if ai.has_method(&"set_fleet_controller"):
		ai.call(&"set_fleet_controller", controller)


func get_fleet_controller() -> FleetAIController:
	return _fleet_controller_ref.get_ref() as FleetAIController \
		if _fleet_controller_ref != null else null


func on_fleet_tactical_context_changed(context: FleetMemberContext) -> void:
	_fleet_tactical_context = context
	if ai.has_method(&"set_fleet_tactical_context"):
		ai.call(&"set_fleet_tactical_context", context)


func get_fleet_tactical_context() -> FleetMemberContext:
	return _fleet_tactical_context

func get_turrets() -> Array:
	# Deprecated: compatibility only. Use get_weapon_mounts().
	return combat.turrets


func get_weapon_mounts() -> Array[WeaponMount]:
	return combat.weapon_mounts

func get_engine_output() -> float:
	return movement.engine_output

func get_speed_knots_style() -> float:
	return movement.get_speed()


func get_world_velocity() -> Vector3:
	return velocity


func get_primary_impact_point(gravity: float) -> Variant:
	return combat.get_primary_impact_point(gravity)


func get_defense_stats() -> ShipDefenseStats:
	return health.get_defense_stats()


func apply_damage(damage: float, penetration_result: int, hit_info: HitInfo) -> float:
	return health.apply_damage(damage, penetration_result, hit_info)


func apply_damage_result(result: DamageResult) -> float:
	return health.apply_damage_result(result)


func apply_flooding(
		duration_seconds: float,
		damage_per_second: float,
		source: HitInfo
) -> void:
	damage_status.apply_flooding(duration_seconds, damage_per_second, source)


func get_current_hp() -> float:
	return health.current_health


func is_alive() -> bool:
	return not _is_sinking and health != null and health.current_health > 0.0 \
		and not is_queued_for_deletion()


func is_hostile_to(other_ship: Node) -> bool:
	if other_ship == null:
		return false
	return FactionRelations.are_hostile(team, StringName(str(other_ship.get(&"team"))))


func get_navigation_safety_radius_m() -> float:
	return ship_data.navigation_safety_radius_m if ship_data != null else 0.0


func sink() -> void:
	if _is_sinking:
		return
	_is_sinking = true
	set_physics_process(false)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if battle_services != null:
		battle_services.events.emit_ship_destroyed(self)
	call_deferred(&"queue_free")

func _register_groups() -> void:
	add_to_group("ships")
	add_to_group("team_%s" % String(team))

func _setup_components() -> void:
	if weapon_loadout == null:
		weapon_loadout = ShipWeaponLoadout.from_ship_data(ship_data)
	_repair_weapon_loadout()
	visual_builder.setup(
		hull_collision,
		hull_mesh,
		bow_mesh,
		deck_mesh,
		weapon_mount_root
	)
	var built_mounts: Array[WeaponMount] = visual_builder.build(
		ship_data,
		weapon_loadout,
		team,
		team_color,
		self,
		turret_scene
	)
	_apply_runtime_stats_to_mounts(built_mounts)
	var bounds := get_tree().get_first_node_in_group(&"battlefield_bounds") as BattlefieldBounds
	var settings := bounds.settings if bounds != null else preload("res://resources/settings/default_battlefield_settings.tres")
	movement.setup(self, ship_data, engine_output_change_rate, settings.sea_level_m)
	navigation.setup(self, settings, bounds)
	avoidance.setup(self, settings)
	buoyancy.water_height = settings.sea_level_m
	combat.setup(self, built_mounts)
	health.setup(
		ship_data.defense_stats if ship_data != null else null,
		battle_services
	)
	damage_status.setup(battle_services)
	targeting.setup(self, ship_data.ai_role_profile if ship_data != null else null, _ai_candidate_provider)
	ai.setup(self, ship_data)
	if not targeting.target_changed.is_connected(_on_target_changed):
		targeting.target_changed.connect(_on_target_changed)
	if not health.died.is_connected(_on_health_died):
		health.died.connect(_on_health_died)
	if not health.damage_result_applied.is_connected(_on_damage_result_applied):
		health.damage_result_applied.connect(_on_damage_result_applied)
	_setup_carrier_components()


func _setup_carrier_components() -> void:
	var has_air_group := ship_data != null \
		and ship_data.carrier_air_group_data != null \
		and carrier_air_group != null
	if carrier_air_group != null:
		if has_air_group:
			carrier_air_group.setup(
				self,
				ship_data.carrier_air_group_data,
				battle_services
			)
			carrier_air_group.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			carrier_air_group.setup(self, null, battle_services)
			carrier_air_group.process_mode = Node.PROCESS_MODE_DISABLED
	var enable_air_group_ai := has_air_group \
		and not player_controlled \
		and carrier_air_group_ai != null
	if carrier_air_group_ai != null:
		if enable_air_group_ai:
			carrier_air_group_ai.process_mode = \
				Node.PROCESS_MODE_INHERIT
			carrier_air_group_ai.setup(self, carrier_air_group)
		else:
			carrier_air_group_ai.shutdown()
			carrier_air_group_ai.process_mode = Node.PROCESS_MODE_DISABLED


func _rebuild_weapon_mounts() -> void:
	var previous_target = combat.target
	var previous_aim_point := combat.aim_point
	var previous_has_aim_point := combat.has_aim_point
	var previous_aim_mode := combat.aim_mode
	var previous_manual_command := combat.get_manual_aim_command()
	_capture_runtime_stats_from_mounts()
	_repair_weapon_loadout()
	var built_mounts: Array[WeaponMount] = visual_builder.build(
		ship_data,
		weapon_loadout,
		team,
		team_color,
		self,
		turret_scene
	)
	_apply_runtime_stats_to_mounts(built_mounts)
	combat.setup(self, built_mounts)
	if previous_aim_mode \
			== ShipCombat.AimMode.MANUAL_RELATIVE_BEARING \
			and previous_manual_command != null:
		combat.apply_manual_aim_command(previous_manual_command)
	elif is_instance_valid(previous_target):
		combat.set_target(previous_target)
		combat.set_aim_point(previous_aim_point)
	elif previous_has_aim_point:
		combat.set_aim_point(previous_aim_point)


func _repair_weapon_loadout() -> void:
	if weapon_loadout == null:
		weapon_loadout = ShipWeaponLoadout.from_ship_data(ship_data)
	var repair_warnings := weapon_loadout.repair_against_ship(
		ship_data,
		_weapon_database
	)
	for warning in repair_warnings:
		push_warning("Ship '%s': %s" % [ship_id, warning])


func _capture_runtime_stats_from_mounts() -> void:
	if combat == null:
		return
	for mount in combat.weapon_mounts:
		if not is_instance_valid(mount) or mount.slot_data == null:
			continue
		weapon_runtime_stats_by_slot[String(mount.slot_data.slot_id)] = \
			mount.runtime_stats.duplicate_stats()


func _apply_runtime_stats_to_mounts(
		mounts: Array[WeaponMount]
) -> void:
	for mount in mounts:
		if not is_instance_valid(mount) or mount.slot_data == null:
			continue
		var stats := get_weapon_runtime_stats(mount.slot_data.slot_id)
		mount.set_runtime_stats(stats)


func _find_weapon_slot(slot_id: StringName) -> ShipWeaponSlotData:
	if ship_data == null:
		return null
	for slot in ship_data.weapon_slots:
		if slot != null and slot.slot_id == slot_id:
			return slot
	return null


func _on_health_died() -> void:
	if carrier_air_group_ai != null:
		carrier_air_group_ai.shutdown()
		carrier_air_group_ai.process_mode = Node.PROCESS_MODE_DISABLED
	if carrier_air_group != null:
		carrier_air_group.resolve_carrier_loss()
	sink()


func _on_damage_result_applied(result: DamageResult) -> void:
	if result == null:
		return
	var hit_info := result.hit_info
	if hit_info == null:
		return
	var attacker := hit_info.get_attacker_ship()
	if attacker == null:
		return
	var damage_info := hit_info.projectile_info.duplicate(true)
	damage_info["damage_type"] = result.damage_type
	damage_info["hit_outcome"] = result.hit_outcome
	damage_info["source_ship_instance_id"] = hit_info.source_ship_instance_id
	damage_info["weapon_id"] = hit_info.source_weapon_id
	targeting.register_damage_source(attacker, result.applied_damage, damage_info)


func _on_target_changed(_previous_target: Node3D, next_target: Node3D) -> void:
	ai.set_target(next_target)
	if next_target == null:
		combat.clear_target()
	else:
		combat.set_target(next_target)
	navigation.clear_navigation_target()

func _apply_navigation_movement() -> void:
	var waypoint := navigation.get_current_waypoint()
	var desired_direction := waypoint - global_position
	desired_direction.y = 0.0
	movement.set_navigation_command(
		desired_direction,
		navigation.get_remaining_distance_m(),
		avoidance.steering_offset,
		avoidance.speed_scale
	)
