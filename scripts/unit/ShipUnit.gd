extends CharacterBody3D
class_name ShipUnit

const SHIP_DATABASE_SCRIPT := preload("res://scripts/data/ShipDatabase.gd")

@export var ship_id := "dd_bluewind"
@export var ship_data: ShipData
@export var team: StringName = &"neutral"
@export var fleet_id: StringName = &""
@export var player_controlled := false
@export var team_color := Color(0.2, 0.55, 1.0)
@export var engine_output_change_rate := 0.55
@export var turret_scene: PackedScene = preload("res://scenes/weapon/turret.tscn")

@onready var hull_collision: CollisionShape3D = $HullCollision
@onready var hull_mesh: MeshInstance3D = $HullMesh
@onready var bow_mesh: MeshInstance3D = $BowMesh
@onready var deck_mesh: MeshInstance3D = $DeckMesh
@onready var turret_mounts: Node3D = $TurretMounts
@onready var movement: ShipMovement = $ShipMovement
@onready var navigation: ShipNavigationController = $ShipNavigationController
@onready var avoidance: ShipAvoidanceController = $ShipAvoidanceController
@onready var combat: ShipCombat = $ShipCombat
@onready var health: ShipHealth = $ShipHealth
@onready var targeting: ThreatTargetingComponent = $ThreatTargetingComponent
@onready var ai: ShipAI = $ShipAI
@onready var visual_builder: Node = $ShipVisualBuilder
@onready var buoyancy: Node = $ShipBuoyancy

var _player_throttle_axis := 0.0
var _player_rudder_axis := 0.0
var _player_fire_pressed := false
var _is_sinking: bool = false
var _ai_candidate_provider := Callable()
var _fleet_controller_ref: WeakRef
var _fleet_tactical_context: FleetMemberContext

func setup(data: ShipData, team_name: StringName, is_player: bool, color: Color) -> void:
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
		if _player_fire_pressed:
			combat.fire_all()
	else:
		ai.update_ai(self, movement, navigation, combat, ship_data, delta)
		if navigation.has_navigation_target:
			_apply_navigation_movement()
		else:
			movement.apply_avoidance(avoidance.steering_offset, avoidance.speed_scale)

	movement.apply_movement(delta)
	buoyancy.apply_buoyancy(self)
	combat.update_turrets(self, player_controlled)

func set_player_commands(throttle_axis: float, rudder_axis: float, fire_pressed: bool) -> void:
	_player_throttle_axis = clampf(throttle_axis, -1.0, 1.0)
	_player_rudder_axis = clampf(rudder_axis, -1.0, 1.0)
	_player_fire_pressed = fire_pressed

func set_aim_point(world_point: Vector3) -> void:
	combat.set_aim_point(world_point)

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
	combat.fire_all()

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
	return combat.turrets

func get_engine_output() -> float:
	return movement.engine_output

func get_speed_knots_style() -> float:
	return movement.get_speed()

func get_primary_impact_point(gravity: float) -> Variant:
	return combat.get_primary_impact_point(gravity)


func get_defense_stats() -> ShipDefenseStats:
	return health.get_defense_stats()


func apply_damage(damage: float, penetration_result: int, hit_info: HitInfo) -> float:
	return health.apply_damage(damage, penetration_result, hit_info)


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
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").ship_destroyed.emit(self)
	call_deferred(&"queue_free")

func _register_groups() -> void:
	add_to_group("ships")
	add_to_group("team_%s" % String(team))

func _setup_components() -> void:
	visual_builder.setup(hull_collision, hull_mesh, bow_mesh, deck_mesh, turret_mounts)
	var built_turrets: Array = visual_builder.build(
		ship_data,
		team,
		team_color,
		turret_scene,
		self
	)
	var bounds := get_tree().get_first_node_in_group(&"battlefield_bounds") as BattlefieldBounds
	var settings := bounds.settings if bounds != null else preload("res://resources/settings/default_battlefield_settings.tres")
	movement.setup(self, ship_data, engine_output_change_rate, settings.sea_level_m)
	navigation.setup(self, settings, bounds)
	avoidance.setup(self, settings)
	buoyancy.water_height = settings.sea_level_m
	combat.setup(built_turrets)
	health.setup(ship_data.defense_stats if ship_data != null else null)
	targeting.setup(self, ship_data.ai_role_profile if ship_data != null else null, _ai_candidate_provider)
	ai.setup(self, ship_data)
	if not targeting.target_changed.is_connected(_on_target_changed):
		targeting.target_changed.connect(_on_target_changed)
	if not health.died.is_connected(_on_health_died):
		health.died.connect(_on_health_died)
	if not health.damage_applied.is_connected(_on_damage_applied):
		health.damage_applied.connect(_on_damage_applied)


func _on_health_died() -> void:
	sink()


func _on_damage_applied(
		amount: float,
		_penetration_result: int,
		hit_info: HitInfo
) -> void:
	if hit_info == null:
		return
	var attacker := hit_info.get_attacker_ship()
	if attacker == null:
		return
	var damage_info := hit_info.projectile_info.duplicate(true)
	damage_info["source_ship_instance_id"] = hit_info.source_ship_instance_id
	damage_info["weapon_id"] = hit_info.source_weapon_id
	targeting.register_damage_source(attacker, amount, damage_info)


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
