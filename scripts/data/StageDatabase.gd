extends RefCounted
class_name StageDatabase

const STAGE_DATA_SCRIPT := preload("res://scripts/data/StageData.gd")

func get_stage(stage_id: String) -> StageData:
	var definitions := _definitions()
	if not definitions.has(stage_id):
		push_warning("Unknown stage id '%s'. Falling back to test_level." % stage_id)
		stage_id = "test_level"
	if not definitions.has(stage_id):
		push_warning("StageDatabase is missing fallback test_level. Returning empty StageData.")
		var fallback_stage := STAGE_DATA_SCRIPT.new() as StageData
		fallback_stage.id = "test_level"
		return fallback_stage

	var definition: Dictionary = definitions[stage_id]
	var stage := STAGE_DATA_SCRIPT.new() as StageData
	stage.id = stage_id
	stage.display_name = str(definition.get("display_name", stage_id))
	stage.sea_id = str(definition.get("sea_id", "test_sea"))
	stage.difficulty = float(definition.get("difficulty", 1.0))
	stage.player_ship_id = str(definition.get("player_ship_id", "dd_bluewind"))
	stage.ally_spawns = definition.get("ally_spawns", []).duplicate(true)
	stage.enemy_spawns = definition.get("enemy_spawns", []).duplicate(true)
	stage.reward_table_id = str(definition.get("reward_table_id", ""))
	stage.next_stage_candidates = _to_string_array(definition.get("next_stage_candidates", []))
	return stage

func _definitions() -> Dictionary:
	return {
		"test_level": {
			"display_name": "Test Level",
			"sea_id": "test_sea",
			"difficulty": 1.0,
			"player_ship_id": "dd_bluewind",
			"reward_table_id": "test_rewards",
			"next_stage_candidates": ["test_level"],
			"ally_spawns": [
				{
					"ship_id": "cl_tidebreaker",
					"spawn_name": "AllyCruiser",
					"team": "ally",
					"color": Color(0.12, 0.68, 0.88),
				},
				{
					"ship_id": "cv_seabastion",
					"spawn_name": "AllyCarrier",
					"team": "ally",
					"color": Color(0.16, 0.62, 0.78),
				},
			],
			"enemy_spawns": [
				{
					"ship_id": "dd_bluewind",
					"spawn_name": "EnemyDestroyer",
					"team": "enemy",
					"color": Color(0.9, 0.18, 0.14),
				},
				{
					"ship_id": "cl_tidebreaker",
					"spawn_name": "EnemyCruiser",
					"team": "enemy",
					"color": Color(0.78, 0.12, 0.18),
				},
				{
					"ship_id": "bb_ironwake",
					"spawn_name": "EnemyBattleship",
					"team": "enemy",
					"color": Color(0.64, 0.08, 0.1),
				},
			],
		},
	}

func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
