extends RefCounted
class_name ShipFactory

var ship_scene: PackedScene
var ship_database: ShipDatabase
var state_restorer: RunShipStateRestorer
var battle_services: BattleServices


func setup(
		next_ship_scene: PackedScene,
		next_ship_database: ShipDatabase,
		next_state_restorer: RunShipStateRestorer,
		next_battle_services: BattleServices
) -> void:
	ship_scene = next_ship_scene
	ship_database = next_ship_database
	state_restorer = next_state_restorer
	battle_services = next_battle_services


func create_ship(
		request: ShipSpawnRequest,
		parent: Node
) -> ShipCreationResult:
	var result := ShipCreationResult.new()
	if request == null:
		result.error = "Ship spawn request is null."
		return result
	result.requested_ship_id = request.ship_id
	var resolved_id := request.ship_id
	if not ShipDatabase.SHIP_PATHS.has(String(resolved_id)):
		if not request.allow_player_fallback:
			result.error = "Unknown ship id '%s'." % resolved_id
			push_warning(result.error)
			return result
		resolved_id = StringName(GameConfig.DEFAULT_PLAYER_SHIP_ID)
		result.used_fallback = true
	result.resolved_ship_id = resolved_id
	if ship_scene == null or parent == null:
		result.error = "Ship scene or parent is missing."
		return result
	var ship := ship_scene.instantiate() as ShipUnit
	if ship == null:
		result.error = "Ship scene did not instantiate as ShipUnit."
		return result
	var source_data := ship_database.get_ship(String(resolved_id))
	if source_data == null:
		result.error = "ShipData was not found for '%s'." % resolved_id
		ship.queue_free()
		return result
	var ship_data := source_data.duplicate(true) as ShipData
	ship.setup(
		ship_data,
		request.team,
		request.is_player,
		request.color,
		request.weapon_loadout,
		request.weapon_runtime_stats,
		battle_services
	)
	ship.fleet_id = request.fleet_id
	parent.add_child(ship)
	ship.global_transform = request.transform
	if not request.display_name.is_empty():
		ship.name = request.display_name
	if request.is_player and state_restorer != null:
		state_restorer.restore_player_ship(ship)
	if battle_services != null:
		battle_services.publish(&"ship_spawned", [ship])
	result.ship = ship
	return result
