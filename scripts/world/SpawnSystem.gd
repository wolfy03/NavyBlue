extends Node
class_name SpawnSystem

const SHIP_DATABASE_SCRIPT := preload("res://scripts/data/ShipDatabase.gd")

@export var ship_scene: PackedScene = preload("res://scenes/unit/ship.tscn")
@export var spawn_points_path: NodePath = NodePath("../SpawnPoints")

var ship_database := SHIP_DATABASE_SCRIPT.new()
var spawned_units: Array[Node] = []

func spawn_stage(stage_data: StageData, parent: Node) -> Dictionary:
	clear_spawned_units()
	if stage_data == null:
		push_warning("SpawnSystem.spawn_stage() received null StageData.")
		return _empty_spawn_result()
	var spawn_parent := _resolve_parent(parent)
	if spawn_parent == null:
		push_warning("SpawnSystem could not resolve a parent for stage '%s'." % stage_data.id)
		return _empty_spawn_result()

	var player_info := stage_data.player_spawn.duplicate(true)
	player_info["ship_id"] = str(player_info.get("ship_id", stage_data.player_ship_id))
	player_info["name"] = str(player_info.get("name", "Player"))
	player_info["team"] = str(player_info.get("team", "player"))
	player_info["is_player"] = true
	var player_ship := spawn_player_ship(stage_data.player_ship_id, player_info, spawn_parent)
	var allies := spawn_ally_fleet(stage_data.ally_spawns, spawn_parent)
	var enemies := spawn_enemy_fleet(stage_data.enemy_spawns, spawn_parent)
	return {
		"player_ship": player_ship,
		"allies": allies,
		"enemies": enemies,
	}

func spawn_player_ship(ship_id: String, spawn_info: Dictionary, parent: Node) -> Node:
	var info := spawn_info.duplicate(true)
	info["ship_id"] = ship_id if not ship_id.is_empty() else str(info.get("ship_id", "dd_bluewind"))
	info["team"] = str(info.get("team", "player"))
	info["is_player"] = true
	info["color"] = info.get("color", Color(0.18, 0.48, 0.95))
	return _spawn_ship_from_info(info, parent)

func spawn_ally_fleet(ally_spawns: Array, parent: Node) -> Array:
	var allies: Array = []
	for entry in ally_spawns:
		if not entry is Dictionary:
			continue
		var info: Dictionary = entry.duplicate(true)
		info["team"] = str(info.get("team", "ally"))
		info["is_player"] = false
		info["color"] = info.get("color", Color(0.12, 0.68, 0.88))
		var ship := _spawn_ship_from_info(info, parent)
		if ship != null:
			allies.append(ship)
	return allies

func spawn_enemy_fleet(enemy_spawns: Array, parent: Node) -> Array:
	var enemies: Array = []
	for entry in enemy_spawns:
		if not entry is Dictionary:
			continue
		var info: Dictionary = entry.duplicate(true)
		info["team"] = str(info.get("team", "enemy"))
		info["is_player"] = false
		info["color"] = info.get("color", Color(0.78, 0.12, 0.18))
		var ship := _spawn_ship_from_info(info, parent)
		if ship != null:
			enemies.append(ship)
	return enemies

func clear_spawned_units() -> void:
	for unit in spawned_units:
		if is_instance_valid(unit):
			unit.queue_free()
	spawned_units.clear()

func spawn_ship(
		id: String,
		team: StringName,
		is_player: bool,
		spawn: Node3D,
		color: Color,
		parent: Node
) -> Node:
	var info := {
		"ship_id": id,
		"team": String(team),
		"is_player": is_player,
		"color": color,
		"transform": spawn.global_transform if spawn != null else Transform3D.IDENTITY,
		"name": spawn.name if spawn != null else id,
	}
	return _spawn_ship_from_info(info, parent)

func _spawn_ship_from_info(spawn_info: Dictionary, parent: Node) -> Node:
	var ship_id := str(spawn_info.get("ship_id", "dd_bluewind"))
	var spawn_parent := _resolve_parent(parent)
	if ship_scene == null or spawn_parent == null:
		push_warning("SpawnSystem cannot spawn ship '%s' because ship_scene or parent is missing." % ship_id)
		return null
	var ship = ship_scene.instantiate()
	if ship == null:
		push_warning("SpawnSystem failed to instantiate ship scene for '%s'." % ship_id)
		return null
	if not ship.has_method("setup"):
		push_warning("Spawned ship scene for '%s' does not implement setup()." % ship_id)
		ship.queue_free()
		return null
	var source_data := ship_database.get_ship(ship_id)
	if source_data == null:
		push_warning("SpawnSystem could not resolve ship data for '%s'." % ship_id)
		ship.queue_free()
		return null
	var ship_data := source_data.duplicate(true) as ShipData
	var team := StringName(str(spawn_info.get("team", "neutral")))
	var is_player := bool(spawn_info.get("is_player", false))
	var color: Color = spawn_info.get("color", _default_color_for_team(team))
	ship.setup(ship_data, team, is_player, color)
	ship.fleet_id = StringName(str(spawn_info.get("fleet_id", "")))
	spawn_parent.add_child(ship)
	ship.global_transform = _get_spawn_transform(spawn_info)
	var spawn_name := str(spawn_info.get("name", spawn_info.get("spawn_name", "")))
	if not spawn_name.is_empty():
		ship.name = spawn_name
	spawned_units.append(ship)
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").ship_spawned.emit(ship)
	return ship

func _get_spawn_transform(spawn_info: Dictionary) -> Transform3D:
	var explicit_transform: Variant = spawn_info.get("transform", null)
	if explicit_transform is Transform3D:
		return explicit_transform
	if spawn_info.has("position") or spawn_info.has("rotation_y") or spawn_info.has("rotation_degrees"):
		var position := _to_vector3(spawn_info.get("position", Vector3.ZERO))
		var rotation_degrees := _to_vector3(spawn_info.get("rotation_degrees", Vector3.ZERO))
		rotation_degrees.y = float(spawn_info.get("rotation_y", rotation_degrees.y))
		return Transform3D(Basis.from_euler(Vector3(
			deg_to_rad(rotation_degrees.x),
			deg_to_rad(rotation_degrees.y),
			deg_to_rad(rotation_degrees.z)
		)), position)
	var spawn_name := str(spawn_info.get("name", spawn_info.get("spawn_name", "")))
	var marker := _get_spawn_marker(spawn_name)
	return marker.global_transform if marker != null else Transform3D.IDENTITY

func _get_spawn_marker(spawn_name: String) -> Node3D:
	if spawn_name.is_empty():
		return null
	var spawn_points := get_node_or_null(spawn_points_path)
	return spawn_points.get_node_or_null(spawn_name) as Node3D if spawn_points != null else null

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

func _resolve_parent(parent: Node) -> Node:
	if parent != null:
		return parent
	var current_scene := get_tree().current_scene if get_tree() != null else null
	if current_scene != null:
		var ships := current_scene.get_node_or_null("Ships")
		return ships if ships != null else current_scene
	return get_tree().root if get_tree() != null else null

func _default_color_for_team(team: StringName) -> Color:
	match team:
		&"player":
			return Color(0.18, 0.48, 0.95)
		&"ally":
			return Color(0.12, 0.68, 0.88)
		&"enemy":
			return Color(0.78, 0.12, 0.18)
	return Color(0.5, 0.5, 0.5)

func _empty_spawn_result() -> Dictionary:
	return {
		"player_ship": null,
		"allies": [],
		"enemies": [],
	}
