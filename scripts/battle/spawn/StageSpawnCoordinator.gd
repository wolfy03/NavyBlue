extends RefCounted
class_name StageSpawnCoordinator

var ship_factory: ShipFactory
var player_ship_resolver: PlayerShipResolver
var state_restorer: RunShipStateRestorer
var faction_palette: FactionPalette
var spawn_points: Node3D
var debug_settings: BattleDebugSettings


func setup(
		next_ship_factory: ShipFactory,
		next_player_ship_resolver: PlayerShipResolver,
		next_state_restorer: RunShipStateRestorer,
		next_faction_palette: FactionPalette,
		next_spawn_points: Node3D,
		next_debug_settings: BattleDebugSettings
) -> void:
	ship_factory = next_ship_factory
	player_ship_resolver = next_player_ship_resolver
	state_restorer = next_state_restorer
	faction_palette = next_faction_palette
	spawn_points = next_spawn_points
	debug_settings = next_debug_settings


func spawn_stage(
		stage_data: StageData,
		parent: Node,
		test_config: BattleTestConfig = null
) -> StageSpawnResult:
	var result := StageSpawnResult.new()
	if stage_data == null or parent == null:
		result.errors.append("StageData or spawn parent is missing.")
		return result
	var player_resolution := player_ship_resolver.resolve(test_config)
	var player_request := _build_request(
		stage_data.player_spawn,
		player_resolution.ship_id
	)
	player_request.is_player = true
	player_request.team = FactionRelations.PLAYER
	player_request.allow_player_fallback = true
	if state_restorer != null:
		player_request.weapon_loadout = state_restorer \
			.get_player_weapon_loadout(player_request.ship_id)
		player_request.weapon_runtime_stats = state_restorer \
			.get_player_weapon_runtime_stats(player_request.ship_id)
	var player_creation := ship_factory.create_ship(
		player_request,
		parent
	)
	if player_creation.is_success():
		result.player_ship = player_creation.ship
	else:
		result.errors.append(player_creation.error)
	for spawn_data in stage_data.ally_spawns:
		_append_spawn(spawn_data, parent, result.allies, result.errors)
	for spawn_data in stage_data.enemy_spawns:
		_append_spawn(spawn_data, parent, result.enemies, result.errors)
	if debug_settings != null and debug_settings.log_spawn_resolution:
		print_debug(
			"Player ship resolved: id=%s source=%s stage=%s"
			% [
				player_resolution.ship_id,
				player_resolution.get_source_name(),
				stage_data.id,
			]
		)
	return result


func _append_spawn(
		spawn_data: ShipSpawnData,
		parent: Node,
		target: Array[ShipUnit],
		errors: PackedStringArray
) -> void:
	var request := _build_request(spawn_data)
	var creation := ship_factory.create_ship(request, parent)
	if creation.is_success():
		target.append(creation.ship)
	elif not creation.error.is_empty():
		errors.append(creation.error)


func _build_request(
		spawn_data: ShipSpawnData,
		resolved_ship_id: StringName = &""
) -> ShipSpawnRequest:
	var request := ShipSpawnRequest.new()
	if spawn_data == null:
		request.ship_id = resolved_ship_id
		request.allow_player_fallback = not resolved_ship_id.is_empty()
		return request
	request.ship_id = resolved_ship_id \
		if not resolved_ship_id.is_empty() else spawn_data.ship_id
	request.team = spawn_data.team
	request.fleet_id = spawn_data.fleet_id
	request.display_name = spawn_data.display_name
	request.is_player = spawn_data.is_player
	request.color = spawn_data.color_override \
		if spawn_data.use_color_override \
		else faction_palette.get_color(spawn_data.team)
	var marker := spawn_points.get_node_or_null(
		NodePath(spawn_data.spawn_marker_id)
	) as Node3D if spawn_points != null \
		and not spawn_data.spawn_marker_id.is_empty() else null
	request.transform = spawn_data.resolve_transform(marker)
	return request
