extends Node
class_name SpawnSystem

const SHIP_DATABASE_SCRIPT := preload("res://scripts/data/ShipDatabase.gd")

@export var ship_scene: PackedScene = preload("res://scenes/unit/ship.tscn")

var ship_database := SHIP_DATABASE_SCRIPT.new()

func spawn_ship(id: String, team: StringName, is_player: bool, spawn: Node3D, color: Color, parent: Node) -> Node:
	var ship = ship_scene.instantiate()
	ship.setup(ship_database.get_ship(id), team, is_player, color)
	parent.add_child(ship)
	ship.global_transform = spawn.global_transform
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").ship_spawned.emit(ship)
	return ship
