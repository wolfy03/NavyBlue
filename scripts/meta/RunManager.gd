extends Node

const DEFAULT_SEA_ID := "test_sea"
const DEFAULT_STAGE_ID := "test_level"

var is_run_active := false
var current_sea_id := ""
var current_stage_id := ""
var current_stage_index := 0
var active_upgrades: Array[String] = []
var pending_rewards: Array = []
var difficulty := 1.0
var player_ship_state: Dictionary = {}
var started_at_msec := 0

func start_new_run(config: Dictionary = {}) -> void:
	is_run_active = true
	current_sea_id = config.get("sea_id", DEFAULT_SEA_ID)
	current_stage_id = config.get("stage_id", DEFAULT_STAGE_ID)
	current_stage_index = int(config.get("stage_index", 0))
	active_upgrades = _to_string_array(config.get("upgrades", []))
	pending_rewards = config.get("rewards", [])
	difficulty = float(config.get("difficulty", 1.0))
	player_ship_state = config.get("player_ship_state", {})
	started_at_msec = Time.get_ticks_msec()
	_emit_started()
	_emit_updated()

func reset_run() -> void:
	is_run_active = false
	current_sea_id = ""
	current_stage_id = ""
	current_stage_index = 0
	active_upgrades.clear()
	pending_rewards.clear()
	difficulty = 1.0
	player_ship_state.clear()
	started_at_msec = 0
	_emit_updated()

func set_stage(sea_id: String, stage_id: String, stage_index: int) -> void:
	current_sea_id = sea_id
	current_stage_id = stage_id
	current_stage_index = stage_index
	_emit_updated()

func set_difficulty(value: float) -> void:
	difficulty = maxf(0.0, value)
	_emit_updated()

func add_upgrade(upgrade_id: String) -> void:
	if upgrade_id.is_empty():
		return
	active_upgrades.append(upgrade_id)
	_emit_updated()

func set_pending_rewards(rewards: Array) -> void:
	pending_rewards = rewards.duplicate(true)
	_emit_updated()

func clear_pending_rewards() -> void:
	pending_rewards.clear()
	_emit_updated()

func update_player_ship_state(state: Dictionary) -> void:
	player_ship_state = state.duplicate(true)
	_emit_updated()

func capture_player_ship(ship) -> void:
	if ship == null:
		player_ship_state = {}
	else:
		player_ship_state = {
			"ship_id": str(ship.get("ship_id")),
			"engine_output": float(ship.get("engine_output")),
			"position": _vector3_to_dictionary(ship.global_position if ship is Node3D else Vector3.ZERO),
			"rotation": _vector3_to_dictionary(ship.global_rotation if ship is Node3D else Vector3.ZERO),
		}
	_emit_updated()

func finish_run(result: Dictionary = {}) -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").run_finished.emit(result)
	reset_run()

func to_save_data() -> Dictionary:
	return {
		"is_run_active": is_run_active,
		"current_sea_id": current_sea_id,
		"current_stage_id": current_stage_id,
		"current_stage_index": current_stage_index,
		"active_upgrades": active_upgrades,
		"pending_rewards": pending_rewards,
		"difficulty": difficulty,
		"player_ship_state": player_ship_state,
		"started_at_msec": started_at_msec,
	}

func restore_from_save_data(data: Dictionary) -> void:
	is_run_active = bool(data.get("is_run_active", false))
	current_sea_id = data.get("current_sea_id", "")
	current_stage_id = data.get("current_stage_id", "")
	current_stage_index = int(data.get("current_stage_index", 0))
	active_upgrades = _to_string_array(data.get("active_upgrades", []))
	pending_rewards = data.get("pending_rewards", [])
	difficulty = float(data.get("difficulty", 1.0))
	player_ship_state = data.get("player_ship_state", {})
	started_at_msec = int(data.get("started_at_msec", 0))
	_emit_updated()

func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result

func _vector3_to_dictionary(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}

func _emit_started() -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").run_started.emit(current_stage_id)

func _emit_updated() -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").run_updated.emit(to_save_data())
