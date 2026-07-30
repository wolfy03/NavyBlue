extends RefCounted
class_name PlayerShipResolver

var run_session: RunSessionReader
var _warned_invalid_ids: Dictionary = {}


func setup(next_run_session: RunSessionReader) -> void:
	shutdown()
	run_session = next_run_session


func shutdown() -> void:
	run_session = null
	_warned_invalid_ids.clear()


func resolve(test_config: BattleTestConfig = null) -> PlayerShipResolution:
	var result := PlayerShipResolution.new()
	if OS.is_debug_build() \
			and test_config != null \
			and test_config.enabled \
			and not test_config.player_ship_override.is_empty():
		result.ship_id = test_config.player_ship_override
		result.source = PlayerShipResolution.Source.TEST_OVERRIDE
	elif run_session != null and run_session.is_run_active():
		result.ship_id = StringName(
			run_session.get_selected_player_ship_id()
		)
		result.source = PlayerShipResolution.Source.RUN_SELECTION
	else:
		result.ship_id = StringName(GameConfig.DEFAULT_PLAYER_SHIP_ID)
		result.source = PlayerShipResolution.Source.GAME_DEFAULT
	if ShipDatabase.SHIP_PATHS.has(String(result.ship_id)):
		return result
	var invalid_id := result.ship_id
	result.ship_id = StringName(GameConfig.DEFAULT_PLAYER_SHIP_ID)
	result.used_fallback = true
	if not _warned_invalid_ids.has(invalid_id):
		_warned_invalid_ids[invalid_id] = true
		push_warning(
			"Invalid player ship id '%s'. Falling back to '%s'."
			% [invalid_id, result.ship_id]
		)
	return result
