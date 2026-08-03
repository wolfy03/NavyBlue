extends Node3D
class_name BattleScene

const STAGE_DATABASE_SCRIPT := preload("res://scripts/data/StageDatabase.gd")
const DEFAULT_BATTLEFIELD_SETTINGS := preload("res://resources/settings/default_battlefield_settings.tres")
const DEFAULT_BATTLEFIELD_RULES: BattlefieldRules = preload(
	"res://resources/settings/default_battlefield_rules.tres"
)
const DEFAULT_DEBUG_SETTINGS: BattleDebugSettings = preload(
	"res://resources/settings/default_battle_debug_settings.tres"
)

@export var battlefield_settings: BattlefieldSettings = DEFAULT_BATTLEFIELD_SETTINGS
@export var battlefield_rules: BattlefieldRules = DEFAULT_BATTLEFIELD_RULES
@export var debug_settings: BattleDebugSettings = DEFAULT_DEBUG_SETTINGS
@export var stage_override: StageData
@export var test_config: BattleTestConfig

@onready var ships_root: Node3D = get_node_or_null("Ships") as Node3D
@onready var spawn_points: Node3D = get_node_or_null("SpawnPoints") as Node3D
@onready var spawn_system: SpawnSystem = get_node_or_null("SpawnSystem") as SpawnSystem
@onready var battle_state_controller: BattleStateController = \
	get_node_or_null("BattleStateController") as BattleStateController
@onready var battle_environment: BattleEnvironment = \
	get_node_or_null("BattleEnvironment") as BattleEnvironment
@onready var projectiles_root: Node3D = get_node_or_null("Projectiles") as Node3D
@onready var combat_effect_controller: Node = get_node_or_null(
	"CombatEffectController"
)
@onready var combat_effect_presenter: CombatEffectPresenter = get_node_or_null(
	"CombatEffectPresenter"
) as CombatEffectPresenter
@onready var camera: Camera3D = get_node_or_null("RTSCamera") as Camera3D
@onready var input_manager: PlayerInputManager = \
	get_node_or_null("PlayerInputManager") as PlayerInputManager
@onready var carrier_command_controller: CarrierCommandController = \
	get_node_or_null("CarrierCommandController") as CarrierCommandController
@onready var aircraft_selection_controller: AircraftSelectionController = \
	get_node_or_null("AircraftSelectionController") \
	as AircraftSelectionController
@onready var ship_weapon_preview_presentation: \
	ShipWeaponPreviewPresentation = get_node_or_null(
		"ShipWeaponPreviewPresentation"
	) as ShipWeaponPreviewPresentation
@onready var aircraft_command_presentation: AircraftCommandPresentation = \
	get_node_or_null("AircraftCommandPresentation") \
	as AircraftCommandPresentation
@onready var torpedo_targeting_session: TorpedoAttackTargetingSession = \
	get_node_or_null("TorpedoAttackTargetingSession") \
	as TorpedoAttackTargetingSession
@onready var torpedo_attack_arrow: TorpedoAttackArrowPresenter = \
	get_node_or_null("TorpedoAttackArrow") as TorpedoAttackArrowPresenter
var dive_bomb_targeting_session: DiveBombTargetingSession
var dive_bomb_target_preview: DiveBombTargetPreview
@onready var impact_marker: MeshInstance3D = get_node_or_null("ImpactMarker") as MeshInstance3D
@onready var hud: Node = get_node_or_null("HUD")
@onready var carrier_air_group_panel: CarrierAirGroupPanel = get_node_or_null(
	"HUD/CarrierAirGroupPanel"
) as CarrierAirGroupPanel
@onready var aircraft_selection_rect: Control = get_node_or_null(
	"HUD/AircraftSelectionRect"
) as Control
@onready var battlefield_bounds: BattlefieldBounds = get_node_or_null("BattlefieldBounds") as BattlefieldBounds

var player_ship: ShipUnit
var allies: Array[ShipUnit] = []
var enemies: Array[ShipUnit] = []
var gravity := 9.8
var stage_database := STAGE_DATABASE_SCRIPT.new()
var _battle_units: Array = []
var friendly_fleet_ai: FleetAIController
var enemy_fleet_ai: FleetAIController
var _fleet_controllers: Dictionary = {}
var _validated_stage_ids: Dictionary = {}
var battle_services := BattleServices.new()
var _shutdown_started := false
var _shutdown_completed := false
var initialization_result := BattleInitializationResult.new()

func _ready() -> void:
	BattleInputActions.ensure_defaults()
	if not battle_services.setup(
		get_node_or_null("/root/EventBus"),
		get_node_or_null("/root/ObjectPool"),
		get_node_or_null("/root/RunManager"),
		get_node_or_null("/root/GameManager"),
		spawn_system.faction_palette if spawn_system != null else null,
		debug_settings
	):
		push_error("Battle initialization stopped: required services are missing.")
		set_process(false)
		set_physics_process(false)
		if input_manager != null:
			input_manager.set_input_enabled(false)
		initialization_result = BattleInitializationResult.failed(
			&"battle_services_setup_failed"
		)
		return
	battle_services.ai_gunnery_difficulty = \
		_resolve_ai_gunnery_difficulty_profile()
	if combat_effect_presenter != null:
		var typed_effect_controller := combat_effect_controller \
			as CombatEffectController
		if typed_effect_controller != null:
			typed_effect_controller.setup(battle_services.events)
		combat_effect_presenter.setup(
			typed_effect_controller,
			battle_services.events
		)
	if combat_effect_controller == null:
		push_warning(
			"CombatEffectController is missing. Ship impact effects are disabled."
		)
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if battlefield_bounds != null:
		battlefield_bounds.settings = battlefield_settings
	if battle_environment == null:
		battle_environment = BattleEnvironment.new()
		battle_environment.name = "BattleEnvironment"
		add_child(battle_environment)
	battle_environment.setup(
		battlefield_bounds,
		battlefield_rules,
		debug_settings,
		battlefield_settings.sea_level_m
	)
	if spawn_system != null:
		spawn_system.debug_settings = debug_settings
		spawn_system.setup(battle_services)
	if battle_state_controller != null:
		battle_state_controller.setup(battle_services)
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_battle()
	_connect_unit_registry()
	var stage_data := _resolve_stage_data()
	_initialize_battle(stage_data)
	_setup_camera_and_ui()
	if has_node("/root/RunManager") and player_ship != null:
		get_node("/root/RunManager").capture_player_ship(player_ship)
	initialization_result = BattleInitializationResult.completed()

func _process(_delta: float) -> void:
	_update_impact_marker()


func shutdown() -> void:
	if _shutdown_started:
		return
	_shutdown_started = true
	set_process(false)
	set_physics_process(false)
	if input_manager != null:
		input_manager.set_input_enabled(false)
	if torpedo_attack_arrow != null:
		torpedo_attack_arrow.shutdown()
	if torpedo_targeting_session != null:
		torpedo_targeting_session.shutdown()
	if dive_bomb_target_preview != null:
		dive_bomb_target_preview.shutdown()
	if dive_bomb_targeting_session != null:
		dive_bomb_targeting_session.shutdown()
	if aircraft_selection_controller != null:
		aircraft_selection_controller.set_input_enabled(false)
	if aircraft_command_presentation != null:
		aircraft_command_presentation.shutdown()
	if ship_weapon_preview_presentation != null:
		ship_weapon_preview_presentation.shutdown()
	if battle_state_controller != null:
		battle_state_controller.stop_battle()
	for controller_value in _fleet_controllers.values():
		var controller := controller_value as FleetAIController
		if controller != null and is_instance_valid(controller):
			controller.shutdown()
	_fleet_controllers.clear()
	friendly_fleet_ai = null
	enemy_fleet_ai = null
	for unit_value: Variant in get_battle_units():
		if unit_value == null or not is_instance_valid(unit_value):
			continue
		var ship := unit_value as ShipUnit
		if ship != null:
			ship.shutdown_battle_runtime()
	_shutdown_aircraft()
	_shutdown_projectiles()
	if combat_effect_presenter != null:
		combat_effect_presenter.shutdown()
	var typed_effect_controller := \
		combat_effect_controller as CombatEffectController
	if typed_effect_controller != null:
		typed_effect_controller.shutdown()
		typed_effect_controller.clear_pools()
	if spawn_system != null:
		spawn_system.shutdown()
	battle_services.shutdown()
	_shutdown_completed = true


func is_shutdown_completed() -> bool:
	return _shutdown_completed


func _shutdown_aircraft() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(&"aircraft_squadrons"):
		var squadron := node as AircraftSquadron
		if squadron != null \
				and is_instance_valid(squadron) \
				and is_ancestor_of(squadron):
			squadron.shutdown()


func _shutdown_projectiles() -> void:
	if projectiles_root == null:
		return
	for child in projectiles_root.get_children():
		var projectile := child as ProjectileBase
		if projectile != null:
			projectile.recycle_projectile()
			continue
		var rigid_projectile := child as WeaponProjectileBase
		if rigid_projectile != null:
			rigid_projectile.recycle_projectile()
			continue
		if child.has_method(&"despawn"):
			child.call(&"despawn")
		else:
			child.queue_free()


func _exit_tree() -> void:
	shutdown()

func _resolve_stage_data() -> StageData:
	if stage_override != null:
		_sync_stage_to_run(stage_override)
		return stage_override
	var stage_id := "test_level"
	if has_node("/root/RunManager"):
		var run_manager = get_node("/root/RunManager")
		if not run_manager.is_run_active:
			var config := NewRunConfig.new()
			config.starting_ship_id = GameConfig.DEFAULT_PLAYER_SHIP_ID
			config.starting_stage_id = stage_id
			config.starting_sea_id = GameConfig.DEFAULT_STARTING_SEA_ID
			run_manager.start_new_run(config)
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
	if spawn_system == null:
		push_warning("BattleScene cannot initialize battle because SpawnSystem is missing or invalid.")
		return
	if ships_root == null:
		ships_root = _get_or_create_node3d("Ships")
	var spawn_result := spawn_system.spawn_stage(
		stage_data,
		ships_root,
		_resolve_battle_test_config(stage_data)
	)
	player_ship = spawn_result.player_ship
	allies = spawn_result.allies
	enemies = spawn_result.enemies
	for error in spawn_result.errors:
		push_warning("Stage spawn: %s" % error)
	if player_ship == null:
		push_warning("BattleScene spawn result did not include a player ship. Battle start aborted.")
		return
	_apply_active_run_upgrades()
	_register_initial_battle_units()
	if battle_state_controller != null:
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
	if not controller.setup(
		resolved_fleet_id,
		ship.team,
		Callable(self, &"get_battle_units"),
		battlefield_bounds,
		_resolve_ai_difficulty_profile(),
		Callable(self, &"get_incoming_attacker_count"),
		battle_services
	):
		push_error("FleetAI setup failed for fleet '%s'." % resolved_fleet_id)
		remove_child(controller)
		controller.free()
		return null
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


func _resolve_ai_gunnery_difficulty_profile() -> AIGunneryDifficultyProfile:
	var difficulty_value: Variant = null
	if has_node("/root/RunManager"):
		difficulty_value = get_node("/root/RunManager").get(&"difficulty")
	return AIGunneryDifficultyProfileResolver.resolve(difficulty_value)

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
	marker_position.y = battle_environment.sea_level_m + 0.45
	impact_marker.global_position = marker_position
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08
	impact_marker.scale = Vector3(pulse, 1.0, pulse)

func _setup_camera_and_ui() -> void:
	if camera != null:
		(camera as RTSCamera).setup(
			player_ship,
			battlefield_settings,
			battlefield_bounds,
			input_manager,
			battle_environment
		)
	else:
		push_warning("BattleScene camera is missing or does not support setup().")
	if input_manager != null:
		input_manager.battlefield_rules = battlefield_rules
		input_manager.setup(
			player_ship,
			camera,
			battle_environment
		)
		if ship_weapon_preview_presentation != null:
			ship_weapon_preview_presentation.setup(input_manager)
		if aircraft_selection_controller != null:
			aircraft_selection_controller.setup(
				camera,
				aircraft_selection_rect,
				battle_environment,
				battle_services
			)
			input_manager.set_aircraft_selection_controller(
				aircraft_selection_controller
			)
			if aircraft_command_presentation != null:
				aircraft_command_presentation.setup(
					aircraft_selection_controller,
					camera,
					battle_environment
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
		if torpedo_targeting_session != null:
			torpedo_targeting_session.setup(
				input_manager.world_pointer_resolver,
				battle_environment
			)
			input_manager.setup_torpedo_targeting(
				torpedo_targeting_session
			)
			if torpedo_attack_arrow != null:
				torpedo_attack_arrow.setup(torpedo_targeting_session)
		var dive_session := DiveBombTargetingSession.new()
		dive_session.name = "DiveBombTargetingSession"
		add_child(dive_session)
		dive_session.setup(battle_environment)
		input_manager.setup_dive_targeting(dive_session)
		var dive_preview := DiveBombTargetPreview.new()
		dive_preview.name = "DiveBombTargetPreview"
		add_child(dive_preview)
		dive_preview.setup(dive_session)
		dive_bomb_targeting_session = dive_session
		dive_bomb_target_preview = dive_preview
	else:
		push_warning("PlayerInputManager is missing or does not support setup().")
	if hud != null and hud.has_method("setup"):
		hud.setup(player_ship, camera)
		if input_manager != null:
			if not input_manager.command_mode_changed.is_connected(
				hud.set_command_mode
			):
				input_manager.command_mode_changed.connect(
					hud.set_command_mode
				)
			hud.set_command_mode(input_manager.get_command_mode())
		if aircraft_selection_controller != null \
				and not aircraft_selection_controller.command_feedback \
					.is_connected(hud.show_aircraft_command_feedback):
			aircraft_selection_controller.command_feedback.connect(
				hud.show_aircraft_command_feedback
			)
	else:
		push_warning("HUD is missing or does not support setup().")


func _resolve_battle_test_config(
		stage_data: StageData
) -> BattleTestConfig:
	if not OS.is_debug_build():
		return null
	if test_config != null and test_config.enabled:
		return test_config
	if stage_override == null \
			or stage_data == null \
			or stage_data.player_spawn == null \
			or stage_data.player_spawn.ship_id.is_empty():
		return null
	var implicit_config := BattleTestConfig.new()
	implicit_config.enabled = true
	implicit_config.stage_override = stage_data
	implicit_config.player_ship_override = stage_data.player_spawn.ship_id
	return implicit_config

func _get_or_create_node3d(node_name: String) -> Node3D:
	var existing := get_node_or_null(node_name) as Node3D
	if existing != null:
		return existing
	var created := Node3D.new()
	created.name = node_name
	add_child(created)
	return created
