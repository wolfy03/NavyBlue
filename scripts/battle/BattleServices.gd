extends RefCounted
class_name BattleServices

var events := BattleEventPublisher.new()
var projectile_pool := ProjectilePoolService.new()
var projectile_factory := ProjectileFactory.new()
var run_session := RunSessionReader.new()
var game_flow := GameFlowService.new()
var faction_palette: FactionPalette
var debug_settings: BattleDebugSettings


func setup(
		next_event_bus: Node,
		next_object_pool: Node,
		next_run_manager: Node,
		next_game_manager: Node,
		next_faction_palette: FactionPalette,
		next_debug_settings: BattleDebugSettings = null
) -> void:
	shutdown()
	events.setup(next_event_bus)
	projectile_pool.setup(next_object_pool)
	projectile_factory.setup(projectile_pool, self)
	run_session.setup(next_run_manager)
	game_flow.setup(next_game_manager)
	faction_palette = next_faction_palette
	debug_settings = next_debug_settings


func shutdown() -> void:
	events.shutdown()
	projectile_factory.shutdown()
	projectile_pool.shutdown()
	run_session.shutdown()
	game_flow.shutdown()
	faction_palette = null
	debug_settings = null


func get_faction_color(team: StringName, fallback: Color) -> Color:
	if faction_palette == null \
			or faction_palette.get_faction(team) == null:
		return fallback
	return faction_palette.get_color(team)
