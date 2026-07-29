extends Resource
class_name NewRunConfig

@export var starting_ship_id: String = \
	GameConfig.DEFAULT_PLAYER_SHIP_ID
@export var starting_sea_id: String = \
	GameConfig.DEFAULT_STARTING_SEA_ID
@export var starting_stage_id: String = \
	GameConfig.DEFAULT_STARTING_STAGE_ID
@export var difficulty: float = 1.0
@export var starting_gold: int = 0
@export var starting_scrap: int = 0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ShipDatabase.SHIP_PATHS.has(starting_ship_id):
		errors.append(
			"Unsupported starting ship id: %s" % starting_ship_id
		)
	if starting_stage_id.is_empty():
		errors.append("starting_stage_id must not be empty.")
	if starting_sea_id.is_empty():
		errors.append("starting_sea_id must not be empty.")
	if difficulty <= 0.0:
		errors.append("difficulty must be greater than zero.")
	return errors
