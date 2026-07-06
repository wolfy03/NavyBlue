extends Node

var current_stage_id := ""
var player_ship
var run_state: Dictionary = {}

func start_run(stage_id: String) -> void:
	current_stage_id = stage_id
	run_state = {
		"stage_id": stage_id,
		"started_at_msec": Time.get_ticks_msec(),
	}
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").run_started.emit(stage_id)

func register_player_ship(ship) -> void:
	player_ship = ship

func finish_run(result: Dictionary) -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").run_finished.emit(result)
	current_stage_id = ""
	player_ship = null
