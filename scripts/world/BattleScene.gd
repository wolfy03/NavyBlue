extends Node3D
class_name BattleScene

const STAGE_DATABASE_SCRIPT := preload("res://scripts/data/StageDatabase.gd")
const DEFAULT_BATTLEFIELD_SETTINGS := preload("res://resources/settings/default_battlefield_settings.tres")

@export var battlefield_settings: BattlefieldSettings = DEFAULT_BATTLEFIELD_SETTINGS

@onready var ships_root: Node3D = get_node_or_null("Ships") as Node3D
@onready var spawn_points: Node3D = get_node_or_null("SpawnPoints") as Node3D
@onready var spawn_system: Node = get_node_or_null("SpawnSystem")
@onready var battle_state_controller: Node = get_node_or_null("BattleStateController")
@onready var projectiles_root: Node3D = get_node_or_null("Projectiles") as Node3D
@onready var camera: Camera3D = get_node_or_null("RTSCamera") as Camera3D
@onready var input_manager: Node = get_node_or_null("PlayerInputManager")
@onready var impact_marker: MeshInstance3D = get_node_or_null("ImpactMarker") as MeshInstance3D
@onready var hud: Node = get_node_or_null("HUD")
@onready var battlefield_bounds: BattlefieldBounds = get_node_or_null("BattlefieldBounds") as BattlefieldBounds

var player_ship
var allies: Array = []
var enemies: Array = []
var gravity := 9.8
var stage_database := STAGE_DATABASE_SCRIPT.new()

func _ready() -> void:
	BattleInputActions.ensure_defaults()
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if battlefield_bounds != null:
		battlefield_bounds.settings = battlefield_settings
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_battle()
	var stage_data := _resolve_stage_data()
	_initialize_battle(stage_data)
	_setup_camera_and_ui()
	if has_node("/root/RunManager") and player_ship != null:
		get_node("/root/RunManager").capture_player_ship(player_ship)

func _process(_delta: float) -> void:
	_update_impact_marker()

func _resolve_stage_data() -> StageData:
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
	if has_node("/root/RunManager"):
		var active_run_manager = get_node("/root/RunManager")
		active_run_manager.set_stage(stage_data.sea_id, stage_data.id, active_run_manager.current_stage_index)
		active_run_manager.set_difficulty(stage_data.difficulty)
	return stage_data

func _initialize_battle(stage_data: StageData) -> void:
	if stage_data == null:
		push_warning("BattleScene cannot initialize battle without StageData.")
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
	_assign_ai_targets()
	if battle_state_controller != null and battle_state_controller.has_method("start_battle"):
		battle_state_controller.start_battle(stage_data, player_ship, allies, enemies)
	else:
		push_warning("BattleStateController is missing or invalid. Battle result detection is disabled.")

func _spawn_test_fleets_legacy() -> Dictionary:
	if spawn_system == null or not spawn_system.has_method("spawn_stage"):
		return {}
	if ships_root == null:
		ships_root = _get_or_create_node3d("Ships")
	return spawn_system.spawn_stage(stage_database.get_stage("test_level"), ships_root)

func _assign_ai_targets() -> void:
	for ship in allies:
		if is_instance_valid(ship) and ship.has_method("set_ai_target"):
			ship.set_ai_target(_nearest_enemy(ship))
	for ship in enemies:
		if is_instance_valid(ship) and ship.has_method("set_ai_target"):
			ship.set_ai_target(player_ship)

func _assign_ai_targets_from_groups() -> void:
	for ship in get_tree().get_nodes_in_group("ships"):
		if ship == player_ship:
			continue
		if ship.team == &"enemy":
			ship.set_ai_target(player_ship)
		else:
			ship.set_ai_target(_nearest_enemy(ship))

func _nearest_enemy(source):
	if source == null:
		return null
	var best
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("ships"):
		var ship = node
		if ship == null or ship.team == source.team or ship.team == &"player":
			continue
		var distance: float = source.global_position.distance_squared_to(ship.global_position)
		if distance < best_distance:
			best_distance = distance
			best = ship
	return best

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
	impact_marker.global_position = impact

func _setup_camera_and_ui() -> void:
	if camera != null and camera.has_method("setup"):
		camera.setup(player_ship, battlefield_settings, battlefield_bounds)
	else:
		push_warning("BattleScene camera is missing or does not support setup().")
	if input_manager != null and input_manager.has_method("setup"):
		input_manager.setup(player_ship, camera, battlefield_settings.sea_level_m, battlefield_bounds)
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
