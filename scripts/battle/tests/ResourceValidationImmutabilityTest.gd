extends SceneTree

const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)
const PALETTE: FactionPalette = preload(
	"res://resources/factions/default_faction_palette.tres"
)
const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check(STAGE.validate().is_empty(), "test StageData validates")
	_check(PALETTE.validate().is_empty(), "required faction palette validates")
	var original_ship_id := STAGE.player_spawn.ship_id
	var original_team := STAGE.player_spawn.team
	var original_transform := STAGE.player_spawn.explicit_transform
	var original_faction_ids: Array[StringName] = []
	for faction in PALETTE.factions:
		original_faction_ids.append(faction.id)

	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await process_frame
	await physics_frame
	_check(
		STAGE.player_spawn.ship_id == original_ship_id
			and STAGE.player_spawn.team == original_team
			and STAGE.player_spawn.explicit_transform == original_transform,
		"stage spawning does not mutate shared ShipSpawnData"
	)
	var current_faction_ids: Array[StringName] = []
	for faction in PALETTE.factions:
		current_faction_ids.append(faction.id)
	_check(
		current_faction_ids == original_faction_ids,
		"battle setup does not mutate shared faction resources"
	)
	_check(
		battle.player_ship != null
			and battle.player_ship.ship_data != null
			and battle.player_ship.ship_data != ShipDatabase.new().get_ship(
				String(original_ship_id)
			),
		"spawned ship owns runtime ShipData instead of the database Resource"
	)
	battle.queue_free()
	await process_frame
	await physics_frame
	for failure in _failures:
		push_error("RESOURCE IMMUTABILITY: %s" % failure)
	print(
		"RESOURCE_VALIDATION_IMMUTABILITY_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
