extends Node3D
class_name BattleScene

const STAGE_DATABASE_SCRIPT := preload("res://scripts/data/StageDatabase.gd")
const DEFAULT_BATTLEFIELD_SETTINGS := preload("res://resources/settings/default_battlefield_settings.tres")

@export var battlefield_settings: BattlefieldSettings = DEFAULT_BATTLEFIELD_SETTINGS
@export var stage_override: StageData

@onready var ships_root: Node3D = get_node_or_null("Ships") as Node3D
@onready var spawn_points: Node3D = get_node_or_null("SpawnPoints") as Node3D
@onready var spawn_system: Node = get_node_or_null("SpawnSystem")
@onready var battle_state_controller: Node = get_node_or_null("BattleStateController")
@onready var projectiles_root: Node3D = get_node_or_null("Projectiles") as Node3D
@onready var combat_effect_controller: Node = get_node_or_null(
	"CombatEffectController"
)
@onready var camera: Camera3D = get_node_or_null("RTSCamera") as Camera3D
@onready var input_manager: Node = get_node_or_null("PlayerInputManager")
@onready var carrier_command_controller: CarrierCommandController = \
	get_node_or_null("CarrierCommandController") as CarrierCommandController
@onready var aircraft_selection_controller: AircraftSelectionController = \
	get_node_or_null("AircraftSelectionController") \
	as AircraftSelectionController
@onready var impact_marker: MeshInstance3D = get_node_or_null("ImpactMarker") as MeshInstance3D
@onready var hud: Node = get_node_or_null("HUD")
@onready var carrier_air_group_panel: CarrierAirGroupPanel = get_node_or_null(
	"HUD/CarrierAirGroupPanel"
) as CarrierAirGroupPanel
@onready var aircraft_selection_rect: Control = get_node_or_null(
	"HUD/AircraftSelectionRect"
) as Control
@onready var battlefield_bounds: BattlefieldBounds = get_node_or_null("BattlefieldBounds") as BattlefieldBounds

var player_ship
var allies: Array = []
var enemies: Array = []
var gravity := 9.8
var stage_database := STAGE_DATABASE_SCRIPT.new()
var _battle_units: Array = []
var friendly_fleet_ai: FleetAIController
var enemy_fleet_ai: FleetAIController
var _fleet_controllers: Dictionary = {}
var _validated_stage_ids: Dictionary = {}

func _ready() -> void:
	BattleInputActions.ensure_defaults()
	if combat_effect_controller == null:
		push_warning(
			"CombatEffectController is missing. Ship impact effects are disabled."
		)
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if battlefield_bounds != null:
		battlefield_bounds.settings = battlefield_settings
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_battle()
	_connect_unit_registry()
	var stage_data := _resolve_stage_data()
	_initialize_battle(stage_data)
	_setup_camera_and_ui()
	if has_node("/root/RunManager") and player_ship != null:
		get_node("/root/RunManager").capture_player_ship(player_ship)

func _process(_delta: float) -> void:
	_update_impact_marker()

func _resolve_stage_data() -> StageData:
	if stage_override != null:
		_sync_stage_to_run(stage_override)
		return stage_override
	var stage_id := "test_level"
	if has_node("/root/RunManager"):
		var run_manager = get_node("/root/RunManager")
		if not run_manager.is_run_active:
			run_manager.start_new_run({
				"sea_id": "test_sea",
				"stage_id": stage_id,
				"stage_index": 0,
				"difficulty": 1.0,
			})
		stage_id = run_manager.current_stage_id if not str(run_manager.current_stage_id).is_empty() else stage_id
	var stage_data: StageData = stage_database.get_stage(stage_id)
	_sync_stage_to_run(stage_data)
	return stage_data


func _sync_stage_to_run(stage_data: StageData) -> void:
	if stage_data == null:
		return
	if has_node("/root/RunManager"):
		var active_run_manager = get_node("/root/RunManager")
		active_run_manager.set_stage(stage_data.sea_id, stage_data.id, active_run_manager.current_stage_index)
		active_run_manager.set_difficulty(stage_data.difficulty)

func _initialize_battle(stage_data: StageData) -> void:
	if stage_data == null:
		push_warning("BattleScene cannot initialize battle without StageData.")
		return
	if not _validate_stage_data_once(stage_data):
		return
	if spawn_system == null or not spawn_system.has_method("spawn_stage"):
		push_warning("BattleScene cannot initialize battle because SpawnSystem is missing or invalid.")
		return
	if ships_root == null:
		ships_root = _get_or_create_node3d("Ships")
	var spawn_result: Dictionary = spawn_system.spawn_stage(stage_data, ships_root)
	player_ship = spawn_result.get("player_ship")
	allies = spawn_result.get("allies", [])
	enemies = spawn_result.get("enemies", [])
	if player_ship == null:
		push_warning("BattleScene spawn result did not include a player ship. Battle start aborted.")
		return
	_apply_active_run_upgrades()
	_register_initial_battle_units()
	if battle_state_controller != null and battle_state_controller.has_method("start_battle"):
		battle_state_controller.start_battle(stage_data, player_ship, allies, enemies)
	else:
		push_warning("BattleStateController is missing or invalid. Battle result detection is disabled.")


func _validate_stage_data_once(stage_data: StageData) -> bool:
	var validation_key := stage_data.id \
		if not stage_data.id.is_empty() \
		else str(stage_data.get_instance_id())
	if _validated_stage_ids.has(validation_key):
		return bool(_validated_stage_ids[validation_key])
	var errors := stage_data.validate()
	var valid := errors.is_empty()
	_validated_stage_ids[validation_key] = valid
	for error in errors:
		push_warning(
			"Stage '%s' validation failed: %s"
			% [validation_key, error]
		)
	return valid

func _spawn_test_fleets_legacy() -> Dictionary:
	if spawn_system == null or not spawn_system.has_method("spawn_stage"):
		return {}
	if ships_root == null:
		ships_root = _get_or_create_node3d("Ships")
	return spawn_system.spawn_stage(stage_database.get_stage("test_level"), ships_root)

func get_battle_units() -> Array:
	_prune_battle_units()
	return _battle_units.duplicate()


func debug_launch_first_squadron(
		world_position: Vector3
) -> AircraftSquadron:
	var player_carrier := player_ship as ShipUnit
	if player_carrier == null \
			or not is_instance_valid(player_carrier) \
			or player_carrier.ship_data == null \
			or player_carrier.ship_data.ship_class \
				!= ShipData.ShipClass.AIRCRAFT_CARRIER:
		return null
	return player_carrier.debug_launch_first_squadron(world_position)


func debug_recall_all_squadrons() -> void:
	var player_carrier := player_ship as ShipUnit
	if player_carrier != null \
			and is_instance_valid(player_carrier) \
			and player_carrier.ship_data != null \
			and player_carrier.ship_data.ship_class \
				== ShipData.ShipClass.AIRCRAFT_CARRIER:
		player_carrier.debug_recall_all_squadrons()


func debug_launch_carrier_strike(
		carrier: ShipUnit,
		target_ship: ShipUnit
) -> AircraftSquadron:
	if carrier == null or not is_instance_valid(carrier) \
			or target_ship == null or not is_instance_valid(target_ship):
		return null
	return carrier.launch_air_strike(
		"",
		target_ship,
		null
	)


func get_fleet_controllers() -> Array[FleetAIController]:
	var result: Array[FleetAIController] = []
	for controller_value in _fleet_controllers.values():
		var controller := _as_valid_fleet_controller(controller_value)
		if controller != null:
			result.append(controller)
	return result


func get_incoming_attacker_count(target: ShipUnit) -> int:
	return get_incoming_attackers(target).size()


func get_incoming_attackers(target: ShipUnit) -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	var included_ids: Dictionary = {}
	if target == null:
		return result
	for controller in get_fleet_controllers():
		if not FactionRelations.are_hostile(controller.team, target.team):
			continue
		for attacker in controller.assignment_tracker.get_attackers(target):
			var attacker_id := attacker.get_instance_id()
			if not included_ids.has(attacker_id):
				included_ids[attacker_id] = true
				result.append(attacker)
	return result


func _connect_unit_registry() -> void:
	if ships_root == null:
		ships_root = _get_or_create_node3d("Ships")
	if not ships_root.child_entered_tree.is_connected(_on_battle_unit_entered):
		ships_root.child_entered_tree.connect(_on_battle_unit_entered)
	if not ships_root.child_exiting_tree.is_connected(_on_battle_unit_exiting):
		ships_root.child_exiting_tree.connect(_on_battle_unit_exiting)
	for child in ships_root.get_children():
		_register_battle_unit(child)


func _register_initial_battle_units() -> void:
	_register_battle_unit(player_ship)
	for ship in allies:
		_register_battle_unit(ship)
	for ship in enemies:
		_register_battle_unit(ship)


func _apply_active_run_upgrades() -> void:
	if player_ship == null or not has_node("/root/RunManager"):
		return
	var active_run_manager := get_node("/root/RunManager")
	if active_run_manager.active_upgrades.is_empty():
		return
	var upgrade_system := UpgradeSystem.new()
	upgrade_system.apply_upgrades_to_ship(player_ship, active_run_manager.active_upgrades)
	upgrade_system.free()


func _on_battle_unit_entered(node: Node) -> void:
	_register_battle_unit(node)


func _on_battle_unit_exiting(node: Node) -> void:
	var ship := node as ShipUnit
	if ship != null:
		var controller := ship.get_fleet_controller()
		if controller != null:
			controller.unregister_member(ship)
	_battle_units.erase(node)
	allies.erase(node)
	enemies.erase(node)
	if player_ship == node:
		player_ship = null


func _register_battle_unit(node) -> void:
	var ship := node as Node3D
	if ship == null or not ship is ShipUnit:
		return
	if not ship.is_node_ready():
		call_deferred(&"_register_battle_unit", ship)
		return
	if not _battle_units.has(ship):
		_battle_units.append(ship)
	match StringName(str(ship.get(&"team"))):
		FactionRelations.PLAYER:
			if bool(ship.get(&"player_controlled")):
				player_ship = ship
		FactionRelations.ALLY:
			if not allies.has(ship):
				allies.append(ship)
		FactionRelations.ENEMY:
			if not enemies.has(ship):
				enemies.append(ship)
	if ship.has_method(&"configure_ai_target_provider"):
		ship.call(&"configure_ai_target_provider", Callable(self, &"get_battle_units"))
	var fleet_controller := _get_or_create_fleet_controller(ship as ShipUnit)
	if fleet_controller != null:
		fleet_controller.register_member(ship as ShipUnit)


func _prune_battle_units() -> void:
	for index in range(_battle_units.size() - 1, -1, -1):
		var ship_value: Variant = _battle_units[index]
		if ship_value == null or not is_instance_valid(ship_value):
			_battle_units.remove_at(index)
			continue
		var ship := ship_value as Node3D
		if ship == null or ship.is_queued_for_deletion() or not ship.is_inside_tree():
			_battle_units.remove_at(index)


func _get_or_create_fleet_controller(ship: ShipUnit) -> FleetAIController:
	var resolved_fleet_id := ship.fleet_id
	if resolved_fleet_id.is_empty():
		resolved_fleet_id = &"enemy_main" if ship.team == FactionRelations.ENEMY \
			else &"friendly_main"
	var fleet_key := _make_fleet_key(ship.team, resolved_fleet_id)
	if _fleet_controllers.has(fleet_key):
		var existing := _as_valid_fleet_controller(
			_fleet_controllers[fleet_key]
		)
		if existing == null:
			_fleet_controllers.erase(fleet_key)
		elif existing.team != ship.team:
			push_error(
				"Fleet controller team mismatch: fleet_id=%s, existing_team=%s, new_team=%s"
				% [
					String(resolved_fleet_id),
					String(existing.team),
					String(ship.team),
				]
			)
			return null
		else:
			return existing
	var controller := FleetAIController.new()
	controller.name = "FleetAI_%s_%s" % [String(ship.team), String(resolved_fleet_id)]
	add_child(controller)
	controller.setup(
		resolved_fleet_id,
		ship.team,
		Callable(self, &"get_battle_units"),
		battlefield_bounds,
		_resolve_ai_difficulty_profile(),
		Callable(self, &"get_incoming_attacker_count")
	)
	controller.became_empty.connect(_on_fleet_became_empty)
	_fleet_controllers[fleet_key] = controller
	_refresh_primary_fleet_references()
	return controller


func _make_fleet_key(team: StringName, fleet_id: StringName) -> StringName:
	return StringName("%s::%s" % [String(team), String(fleet_id)])


func _on_fleet_became_empty(
		empty_team: StringName,
		empty_fleet_id: StringName
) -> void:
	var fleet_key := _make_fleet_key(empty_team, empty_fleet_id)
	var controller := _as_valid_fleet_controller(
		_fleet_controllers.get(fleet_key)
	)
	if controller == null or not controller.is_empty():
		return
	_fleet_controllers.erase(fleet_key)
	_refresh_primary_fleet_references()
	controller.queue_free()


func _refresh_primary_fleet_references() -> void:
	friendly_fleet_ai = null
	enemy_fleet_ai = null
	for controller_value in _fleet_controllers.values():
		var controller := _as_valid_fleet_controller(controller_value)
		if controller == null or controller.is_queued_for_deletion():
			continue
		if controller.fleet_id == &"enemy_main" \
				and controller.team == FactionRelations.ENEMY:
			enemy_fleet_ai = controller
		elif controller.fleet_id == &"friendly_main" and (
				friendly_fleet_ai == null \
				or controller.team == FactionRelations.ALLY
		):
			friendly_fleet_ai = controller


func _as_valid_fleet_controller(value: Variant) -> FleetAIController:
	if value == null or not is_instance_valid(value):
		return null
	return value as FleetAIController


func _resolve_ai_difficulty_profile() -> AIDifficultyProfile:
	var difficulty := 1.0
	if has_node("/root/RunManager"):
		difficulty = float(get_node("/root/RunManager").get(&"difficulty"))
	if difficulty < 0.85:
		return load("res://resources/ai_difficulty/easy.tres") as AIDifficultyProfile
	if difficulty > 1.25:
		return load("res://resources/ai_difficulty/hard.tres") as AIDifficultyProfile
	return load("res://resources/ai_difficulty/normal.tres") as AIDifficultyProfile

func _update_impact_marker() -> void:
	if impact_marker == null or player_ship == null:
		return
	if not player_ship.has_method("get_primary_impact_point"):
		impact_marker.visible = false
		return
	var impact: Variant = player_ship.get_primary_impact_point(gravity)
	if impact == null:
		impact_marker.visible = false
		return
	impact_marker.visible = true
	var marker_position: Vector3 = impact
	marker_position.y = battlefield_settings.sea_level_m + 0.45
	impact_marker.global_position = marker_position
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08
	impact_marker.scale = Vector3(pulse, 1.0, pulse)

func _setup_camera_and_ui() -> void:
	if camera != null and camera.has_method("setup"):
		camera.setup(player_ship, battlefield_settings, battlefield_bounds)
	else:
		push_warning("BattleScene camera is missing or does not support setup().")
	if input_manager != null and input_manager.has_method("setup"):
		input_manager.setup(player_ship, camera, battlefield_settings.sea_level_m, battlefield_bounds)
		if aircraft_selection_controller != null:
			aircraft_selection_controller.setup(
				camera,
				aircraft_selection_rect,
				battlefield_bounds,
				battlefield_settings.sea_level_m
			)
			input_manager.set_aircraft_selection_controller(
				aircraft_selection_controller
			)
		if carrier_command_controller != null:
			carrier_command_controller.setup(
				camera,
				carrier_air_group_panel,
				aircraft_selection_controller
			)
			input_manager.set_carrier_command_controller(
				carrier_command_controller
			)
	else:
		push_warning("PlayerInputManager is missing or does not support setup().")
	if hud != null and hud.has_method("setup"):
		hud.setup(player_ship, camera)
	else:
		push_warning("HUD is missing or does not support setup().")

func _get_or_create_node3d(node_name: String) -> Node3D:
	var existing := get_node_or_null(node_name) as Node3D
	if existing != null:
		return existing
	var created := Node3D.new()
	created.name = node_name
	add_child(created)
	return created
