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
) -> bool:
	shutdown()
	var dependency_errors := validate_dependencies(
		next_event_bus,
		next_object_pool,
		next_faction_palette
	)
	if not dependency_errors.is_empty():
		for dependency_error in dependency_errors:
			push_error("BattleServices setup failed: %s" % dependency_error)
		return false
	events.setup(next_event_bus)
	projectile_pool.setup(next_object_pool)
	projectile_factory.setup(projectile_pool, self)
	run_session.setup(next_run_manager)
	game_flow.setup(next_game_manager)
	faction_palette = next_faction_palette
	debug_settings = next_debug_settings
	return true


func validate_dependencies(
		next_event_bus: Node,
		next_object_pool: Node,
		next_faction_palette: FactionPalette
) -> PackedStringArray:
	var errors := PackedStringArray()
	if next_event_bus == null:
		errors.append("EventBus is required.")
	if next_object_pool == null:
		errors.append("ObjectPool is required.")
	if next_faction_palette == null:
		errors.append("FactionPalette is required.")
	else:
		for palette_error in next_faction_palette.validate():
			errors.append("FactionPalette: %s" % palette_error)
	return errors


func shutdown() -> void:
	events.shutdown()
	projectile_factory.shutdown()
	projectile_pool.shutdown()
	run_session.shutdown()
	game_flow.shutdown()
	faction_palette = null
	debug_settings = null


func get_faction_color(team: StringName, fallback: Color) -> Color:
	if faction_palette == null:
		return fallback
	var faction := faction_palette.get_faction(team)
	if faction == null:
		faction_palette.warn_unknown_faction_once(team)
		return fallback
	return faction.primary_color
