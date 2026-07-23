extends Node3D
class_name BattleScene

const STAGE_DATABASE_SCRIPT := preload("res://scripts/data/StageDatabase.gd")
const DEFAULT_BATTLEFIELD_SETTINGS := preload("res://resources/settings/default_battlefield_settings.tres")

@export var battlefield_settings: BattlefieldSettings = DEFAULT_BATTLEFIELD_SETTINGS

@onready var ships_root: Node3D = $Ships
@onready var spawn_points: Node3D = $SpawnPoints
@onready var spawn_system: Node = $SpawnSystem
@onready var battle_state_controller: Node = $BattleStateController
@onready var projectiles_root: Node3D = $Projectiles
@onready var camera: Camera3D = $RTSCamera
@onready var input_manager: Node = $PlayerInputManager
@onready var aim_target_marker: MeshInstance3D = $AimTargetMarker
@onready var impact_marker: MeshInstance3D = $ImpactMarker
@onready var hud: HUD = $HUD
@onready var battlefield_bounds: BattlefieldBounds = $BattlefieldBounds
@onready var ballistic_trajectory_renderer: BallisticTrajectoryRenderer = $BallisticTrajectoryRenderer

var player_ship
var allies: Array = []
var enemies: Array = []
var gravity := 9.8
var stage_database := STAGE_DATABASE_SCRIPT.new()

func _ready() -> void:
	BattleInputActions.ensure_defaults()
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	battlefield_bounds.settings = battlefield_settings
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_battle()
	var stage_data := _resolve_stage_data()
	_initialize_battle(stage_data)
	camera.setup(player_ship, battlefield_settings, battlefield_bounds)
	input_manager.setup(player_ship, camera, battlefield_settings.sea_level_m, battlefield_bounds)
	hud.setup(player_ship, camera)
	ballistic_trajectory_renderer.setup(player_ship, battlefield_settings.sea_level_m)
	if has_node("/root/RunManager"):
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
	var spawn_result: Dictionary = spawn_system.spawn_stage(stage_data, ships_root)
	player_ship = spawn_result.get("player_ship")
	allies = spawn_result.get("allies", [])
	enemies = spawn_result.get("enemies", [])
	_assign_ai_targets()
	battle_state_controller.start_battle(stage_data, player_ship, allies, enemies)

func _spawn_test_fleets() -> Dictionary:
	return spawn_system.spawn_stage(stage_database.get_stage("test_level"), ships_root)

func _assign_ai_targets() -> void:
	for ship in allies:
		if is_instance_valid(ship):
			ship.set_ai_target(_nearest_enemy(ship))
	for ship in enemies:
		if is_instance_valid(ship):
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
	if impact_marker == null or aim_target_marker == null or player_ship == null:
		return
	var aim_target: Variant = player_ship.get_current_aim_point()
	if aim_target is Vector3:
		aim_target_marker.visible = true
		aim_target_marker.global_position = aim_target + Vector3.UP * 2.0
	else:
		aim_target_marker.visible = false
	var impact: Variant = player_ship.get_primary_impact_point(gravity)
	if impact == null:
		impact_marker.visible = false
		return
	impact_marker.visible = true
	impact_marker.global_position = impact
