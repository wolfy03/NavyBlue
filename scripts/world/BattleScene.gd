extends Node3D
class_name BattleScene

@onready var ships_root: Node3D = $Ships
@onready var spawn_points: Node3D = $SpawnPoints
@onready var spawn_system: Node = $SpawnSystem
@onready var camera: Camera3D = $RTSCamera
@onready var input_manager: Node = $PlayerInputManager
@onready var impact_marker: MeshInstance3D = $ImpactMarker
@onready var hud: CanvasLayer = $HUD

var player_ship
var gravity := 9.8

func _ready() -> void:
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").enter_battle()
	if has_node("/root/RunManager") and not get_node("/root/RunManager").is_run_active:
		get_node("/root/RunManager").start_new_run({
			"sea_id": "test_sea",
			"stage_id": "test_level",
			"stage_index": 0,
			"difficulty": 1.0,
		})
	_spawn_fleets()
	_assign_ai_targets()
	camera.setup(player_ship)
	input_manager.setup(player_ship, camera, 0.0)
	hud.setup(player_ship)
	if has_node("/root/RunManager"):
		get_node("/root/RunManager").capture_player_ship(player_ship)

func _process(_delta: float) -> void:
	_update_impact_marker()

func _spawn_fleets() -> void:
	player_ship = _spawn_ship("dd_bluewind", &"player", true, "Player", Color(0.18, 0.48, 0.95))
	_spawn_ship("cl_tidebreaker", &"ally", false, "AllyCruiser", Color(0.12, 0.68, 0.88))
	_spawn_ship("cv_seabastion", &"ally", false, "AllyCarrier", Color(0.16, 0.62, 0.78))
	_spawn_ship("dd_bluewind", &"enemy", false, "EnemyDestroyer", Color(0.9, 0.18, 0.14))
	_spawn_ship("cl_tidebreaker", &"enemy", false, "EnemyCruiser", Color(0.78, 0.12, 0.18))
	_spawn_ship("bb_ironwake", &"enemy", false, "EnemyBattleship", Color(0.64, 0.08, 0.1))

func _spawn_ship(id: String, team: StringName, is_player: bool, spawn_name: String, color: Color):
	var spawn := spawn_points.get_node(spawn_name) as Node3D
	return spawn_system.spawn_ship(id, team, is_player, spawn, color, ships_root)

func _assign_ai_targets() -> void:
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
	if impact_marker == null or player_ship == null:
		return
	var impact: Variant = player_ship.get_primary_impact_point(gravity)
	if impact == null:
		impact_marker.visible = false
		return
	impact_marker.visible = true
	impact_marker.global_position = impact
