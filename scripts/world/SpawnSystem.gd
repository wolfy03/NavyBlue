extends Node
class_name SpawnSystem

const DEFAULT_FACTION_PALETTE: FactionPalette = preload(
	"res://resources/factions/default_faction_palette.tres"
)
const DEFAULT_DEBUG_SETTINGS: BattleDebugSettings = preload(
	"res://resources/settings/default_battle_debug_settings.tres"
)

@export var ship_scene: PackedScene = preload(
	"res://scenes/unit/ship.tscn"
)
@export var spawn_points_path: NodePath = NodePath("../SpawnPoints")
@export var faction_palette: FactionPalette = DEFAULT_FACTION_PALETTE
@export var debug_settings: BattleDebugSettings = DEFAULT_DEBUG_SETTINGS

var spawned_units: Array[ShipUnit] = []

var _ship_database := ShipDatabase.new()
var _player_ship_resolver := PlayerShipResolver.new()
var _state_restorer := RunShipStateRestorer.new()
var _ship_factory := ShipFactory.new()
var _stage_coordinator := StageSpawnCoordinator.new()
var _initialized := false


func setup(services: BattleServices) -> void:
	shutdown()
	if services == null:
		push_error("SpawnSystem requires BattleServices.")
		return
	_player_ship_resolver.setup(services.run_session)
	_state_restorer.setup(services.run_session)
	_ship_factory.setup(
		ship_scene,
		_ship_database,
		_state_restorer,
		services
	)
	_stage_coordinator.setup(
		_ship_factory,
		_player_ship_resolver,
		_state_restorer,
		faction_palette,
		get_node_or_null(spawn_points_path) as Node3D,
		debug_settings
	)
	_initialized = true


func shutdown() -> void:
	clear_spawned_units()
	_stage_coordinator.shutdown()
	_ship_factory.shutdown()
	_player_ship_resolver.shutdown()
	_state_restorer.shutdown()
	_initialized = false


func spawn_stage(
		stage_data: StageData,
		parent: Node,
		test_config: BattleTestConfig = null
) -> StageSpawnResult:
	clear_spawned_units()
	if not _initialized:
		push_error(
			"SpawnSystem must be setup by the battle composition root."
		)
		return StageSpawnResult.failed(
			PackedStringArray(["Missing StageSpawnCoordinator."])
		)
	var result := _stage_coordinator.spawn_stage(
		stage_data,
		_resolve_parent(parent),
		test_config
	)
	spawned_units = result.get_all_ships()
	return result


func clear_spawned_units() -> void:
	for unit in spawned_units:
		if unit != null and is_instance_valid(unit):
			unit.queue_free()
	spawned_units.clear()


func _resolve_parent(parent: Node) -> Node:
	if parent != null:
		return parent
	var current_scene := get_tree().current_scene \
		if get_tree() != null else null
	if current_scene != null:
		var ships := current_scene.get_node_or_null("Ships")
		return ships if ships != null else current_scene
	return get_tree().root if get_tree() != null else null


func _exit_tree() -> void:
	shutdown()
