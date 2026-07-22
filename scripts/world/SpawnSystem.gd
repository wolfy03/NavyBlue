extends Node
class_name SpawnSystem

const SHIP_DATABASE_SCRIPT := preload("res://scripts/data/ShipDatabase.gd")

@export var ship_scene: PackedScene = preload("res://scenes/unit/ship.tscn")
@export var spawn_points_path: NodePath = NodePath("../SpawnPoints")

var ship_database := SHIP_DATABASE_SCRIPT.new()
var spawned_units: Array[Node] = []

func spawn_stage(stage_data: StageData, parent: Node) -> Dictionary:
	clear_spawned_units()
	var player_spawn := _make_spawn_entry(stage_data.player_ship_id, "Player", &"player", true, Color(0.18, 0.48, 0.95))
	var player_ship := spawn_player_ship(
		stage_data.player_ship_id,
		_get_spawn_transform(player_spawn),
		parent
	)
	var allies := spawn_ally_fleet(stage_data.ally_spawns, parent)
	var enemies := spawn_enemy_fleet(stage_data.enemy_spawns, parent)
	return {
		"player_ship": player_ship,
		"allies": allies,
		"enemies": enemies,
	}

func spawn_player_ship(ship_id: String, spawn_transform: Transform3D, parent: Node) -> Node:
	var ship := _spawn_ship_from_transform(ship_id, &"player", true, spawn_transform, Color(0.18, 0.48, 0.95), parent)
	return ship

func spawn_ally_fleet(ally_spawns: Array, parent: Node) -> Array:
	var allies: Array = []
	for entry in ally_spawns:
		if not entry is Dictionary:
			continue
		var spawn_entry: Dictionary = entry
		var ship_id := str(spawn_entry.get("ship_id", "dd_bluewind"))
		var team := StringName(str(spawn_entry.get("team", "ally")))
		var color: Color = spawn_entry.get("color", Color(0.12, 0.68, 0.88))
		var ship := _spawn_ship_from_transform(ship_id, team, false, _get_spawn_transform(spawn_entry), color, parent)
		allies.append(ship)
	return allies

func spawn_enemy_fleet(enemy_spawns: Array, parent: Node) -> Array:
	var enemies: Array = []
	for entry in enemy_spawns:
		if not entry is Dictionary:
			continue
		var spawn_entry: Dictionary = entry
		var ship_id := str(spawn_entry.get("ship_id", "dd_bluewind"))
		var team := StringName(str(spawn_entry.get("team", "enemy")))
		var color: Color = spawn_entry.get("color", Color(0.78, 0.12, 0.18))
		var ship := _spawn_ship_from_transform(ship_id, team, false, _get_spawn_transform(spawn_entry), color, parent)
		enemies.append(ship)
	return enemies

func clear_spawned_units() -> void:
	for unit in spawned_units:
		if is_instance_valid(unit):
			unit.queue_free()
	spawned_units.clear()

func spawn_ship(id: String, team: StringName, is_player: bool, spawn: Node3D, color: Color, parent: Node) -> Node:
	if spawn == null:
		return _spawn_ship_from_transform(id, team, is_player, Transform3D.IDENTITY, color, parent)
	return _spawn_ship_from_transform(id, team, is_player, spawn.global_transform, color, parent)

func _spawn_ship_from_transform(id: String, team: StringName, is_player: bool, spawn_transform: Transform3D, color: Color, parent: Node) -> Node:
	var ship = ship_scene.instantiate()
	ship.setup(ship_database.get_ship(id), team, is_player, color)
	parent.add_child(ship)
	ship.global_transform = spawn_transform
	spawned_units.append(ship)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").ship_spawned.emit(ship)
	return ship

func _get_spawn_transform(spawn_entry: Dictionary) -> Transform3D:
	var explicit_transform: Variant = spawn_entry.get("transform", null)
	if explicit_transform is Transform3D:
		return explicit_transform

	var spawn_name := str(spawn_entry.get("spawn_name", ""))
	var marker := _get_spawn_marker(spawn_name)
	if marker != null:
		return marker.global_transform

	var position := _to_vector3(spawn_entry.get("position", Vector3.ZERO))
	var rotation_degrees := _to_vector3(spawn_entry.get("rotation_degrees", Vector3.ZERO))
	var transform := Transform3D.IDENTITY
	transform.origin = position
	transform.basis = Basis.from_euler(Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	))
	return transform

func _get_spawn_marker(spawn_name: String) -> Node3D:
	if spawn_name.is_empty():
		return null
	var spawn_points := get_node_or_null(spawn_points_path)
	if spawn_points == null:
		return null
	return spawn_points.get_node_or_null(spawn_name) as Node3D

func _make_spawn_entry(ship_id: String, spawn_name: String, team: StringName, is_player: bool, color: Color) -> Dictionary:
	return {
		"ship_id": ship_id,
		"spawn_name": spawn_name,
		"team": String(team),
		"is_player": is_player,
		"color": color,
	}

func _to_vector3(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("z", 0.0))
		)
	return Vector3.ZERO
