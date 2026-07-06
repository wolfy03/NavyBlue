extends Resource
class_name StageData

@export var id := "test_level"
@export var display_name := "Test Level"
@export var player_ship_id := "dd_bluewind"
@export var ally_ship_ids: Array[String] = ["cl_tidebreaker", "cv_seabastion"]
@export var enemy_ship_ids: Array[String] = ["dd_bluewind", "cl_tidebreaker", "bb_ironwake"]

