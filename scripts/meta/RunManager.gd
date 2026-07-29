extends Node

const DEFAULT_SEA_ID := GameConfig.DEFAULT_STARTING_SEA_ID
const DEFAULT_STAGE_ID := GameConfig.DEFAULT_STARTING_STAGE_ID
const SAVE_VERSION := 2
const PLAYER_CARRIER_KEY := "player_carrier"

var is_run_active := false
var current_sea_id := ""
var current_stage_id := ""
var current_stage_index := 0
var active_upgrades: Array[String] = []
var pending_rewards: Array = []
var difficulty := 1.0
var currency: Dictionary = {
	"gold": 0,
	"scrap": 0,
}
var player_ship_state: Dictionary = {}
var selected_player_ship_id: String = GameConfig.DEFAULT_PLAYER_SHIP_ID
var carrier_air_group_states: Dictionary = {}
var world_state: Dictionary = {}
var started_at_msec := 0

func start_new_run(config_or_data: Variant = {}) -> void:
	if config_or_data is NewRunConfig:
		_start_new_run_from_config(config_or_data as NewRunConfig)
	elif config_or_data is Dictionary:
		_start_new_run_from_legacy_dictionary(
			config_or_data as Dictionary
		)
	else:
		push_warning("RunManager received an unsupported new-run config.")
		_start_new_run_from_config(NewRunConfig.new())


func _start_new_run_from_config(config: NewRunConfig) -> void:
	var errors := config.validate()
	if not errors.is_empty():
		push_warning(errors[0])
		config = NewRunConfig.new()
	selected_player_ship_id = _validated_ship_id(
		config.starting_ship_id
	)
	_start_new_run_from_legacy_dictionary({
		"sea_id": config.starting_sea_id,
		"stage_id": config.starting_stage_id,
		"stage_index": 0,
		"difficulty": config.difficulty,
		"currency": {
			"gold": config.starting_gold,
			"scrap": config.starting_scrap,
		},
		"player_ship_state": {
			"ship_id": selected_player_ship_id,
		},
	})


func _start_new_run_from_legacy_dictionary(config: Dictionary) -> void:
	is_run_active = true
	current_sea_id = config.get("sea_id", DEFAULT_SEA_ID)
	current_stage_id = config.get("stage_id", DEFAULT_STAGE_ID)
	current_stage_index = int(config.get("stage_index", 0))
	active_upgrades = _to_string_array(config.get("upgrades", []))
	pending_rewards = _to_upgrade_id_array(config.get("rewards", []))
	difficulty = float(config.get("difficulty", 1.0))
	currency = config.get("currency", {"gold": 0, "scrap": 0})
	player_ship_state = config.get("player_ship_state", {})
	selected_player_ship_id = _validated_ship_id(str(
		player_ship_state.get(
			"ship_id",
			config.get("selected_player_ship_id", selected_player_ship_id)
		)
	))
	player_ship_state["ship_id"] = selected_player_ship_id
	var configured_carrier_states: Variant = config.get(
		"carrier_air_group_states",
		{}
	)
	carrier_air_group_states = (
		(configured_carrier_states as Dictionary).duplicate(true)
		if configured_carrier_states is Dictionary else {}
	)
	world_state = config.get("world_state", {})
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
	currency = {
		"gold": 0,
		"scrap": 0,
	}
	player_ship_state.clear()
	selected_player_ship_id = GameConfig.DEFAULT_PLAYER_SHIP_ID
	carrier_air_group_states.clear()
	world_state.clear()
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
	pending_rewards = _to_upgrade_id_array(rewards)
	_emit_updated()

func clear_pending_rewards() -> void:
	pending_rewards.clear()
	_emit_updated()

func set_currency(next_currency: Dictionary) -> void:
	currency = next_currency.duplicate(true)
	_emit_updated()

func add_currency(currency_id: String, amount: int) -> void:
	if currency_id.is_empty():
		return
	currency[currency_id] = int(currency.get(currency_id, 0)) + amount
	_emit_updated()

func update_player_ship_state(state: Dictionary) -> void:
	player_ship_state = state.duplicate(true)
	var ship_id := str(player_ship_state.get("ship_id", ""))
	if not ship_id.is_empty():
		selected_player_ship_id = _validated_ship_id(ship_id)
	player_ship_state["ship_id"] = selected_player_ship_id
	_emit_updated()

func update_world_state(state: Dictionary) -> void:
	world_state = state.duplicate(true)
	_emit_updated()

func capture_player_ship(ship) -> void:
	if ship == null:
		player_ship_state = {}
	else:
		var current_hp := float(ship.get_current_hp()) \
			if ship.has_method(&"get_current_hp") else 0.0
		var maximum_hp := float(ship.health.max_health) \
			if ship is ShipUnit and ship.health != null else current_hp
		player_ship_state = {
			"ship_id": str(ship.get("ship_id")),
			"current_hp": current_hp,
			"maximum_hp": maximum_hp,
			"hp_ratio": current_hp / maxf(maximum_hp, 1.0),
			"engine_output": ship.get_engine_output() if ship.has_method("get_engine_output") else 0.0,
			"position": _vector3_to_dictionary(ship.global_position if ship is Node3D else Vector3.ZERO),
			"rotation": _vector3_to_dictionary(ship.global_rotation if ship is Node3D else Vector3.ZERO),
			"weapon_loadout": ship.get_weapon_loadout_save_data() \
				if ship.has_method("get_weapon_loadout_save_data") else {},
			"weapon_runtime_stats": ship.get_weapon_runtime_stats_save_data() \
				if ship.has_method("get_weapon_runtime_stats_save_data") else {},
			"damage_status": ship.damage_status.to_save_data() \
				if ship is ShipUnit and ship.damage_status != null else {},
		}
		selected_player_ship_id = _validated_ship_id(
			str(player_ship_state.get("ship_id", ""))
		)
		var ship_unit := ship as ShipUnit
		if ship_unit != null \
				and ship_unit.ship_data != null \
				and ship_unit.ship_data.carrier_air_group_data != null:
			capture_carrier_air_group(ship_unit)
		elif ship_unit != null and ship_unit.player_controlled:
			carrier_air_group_states.erase(PLAYER_CARRIER_KEY)
	_emit_updated()


func capture_carrier_air_group(carrier: ShipUnit) -> void:
	if carrier == null or not is_instance_valid(carrier) \
			or carrier.carrier_air_group == null \
			or carrier.ship_data == null \
			or carrier.ship_data.carrier_air_group_data == null:
		return
	var carrier_key := _get_carrier_key(carrier)
	var group_state := carrier.carrier_air_group.to_save_data()
	carrier_air_group_states[carrier_key] = {
		"ship_id": carrier.ship_id,
		"air_group_id": carrier.ship_data.carrier_air_group_data.id,
		"squadrons": (
			group_state.get("squadrons", {}) as Dictionary
		).duplicate(true),
	}


func restore_carrier_air_group(carrier: ShipUnit) -> void:
	if carrier == null or not is_instance_valid(carrier) \
			or carrier.carrier_air_group == null \
			or carrier.ship_data == null \
			or carrier.ship_data.carrier_air_group_data == null:
		return
	var saved_value: Variant = carrier_air_group_states.get(
		_get_carrier_key(carrier),
		{}
	)
	if not saved_value is Dictionary:
		return
	var saved := saved_value as Dictionary
	var saved_ship_id := str(saved.get("ship_id", ""))
	if not saved_ship_id.is_empty() \
			and saved_ship_id != carrier.ship_id:
		push_warning(
			"Saved carrier ship '%s' does not match '%s'."
			% [saved_ship_id, carrier.ship_id]
		)
		return
	var saved_air_group_id := str(saved.get("air_group_id", ""))
	var current_air_group_id := \
		carrier.ship_data.carrier_air_group_data.id
	if not saved_air_group_id.is_empty() \
			and saved_air_group_id != current_air_group_id:
		push_warning(
			"Saved air group '%s' does not match '%s'."
			% [saved_air_group_id, current_air_group_id]
		)
		return
	carrier.carrier_air_group.restore_from_save_data(
		saved.duplicate(true)
	)


func clear_carrier_air_group_state(carrier_key: String) -> void:
	carrier_air_group_states.erase(carrier_key)
	_emit_updated()

func finish_run(result: Dictionary = {}) -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").run_finished.emit(result)
	reset_run()

func to_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"is_run_active": is_run_active,
		"current_sea_id": current_sea_id,
		"current_stage_id": current_stage_id,
		"current_stage_index": current_stage_index,
		"active_upgrades": active_upgrades.duplicate(),
		"pending_rewards": pending_rewards.duplicate(true),
		"difficulty": difficulty,
		"currency": currency.duplicate(true),
		"player_ship_state": player_ship_state.duplicate(true),
		"selected_player_ship_id": selected_player_ship_id,
		"carrier_air_group_states":
			carrier_air_group_states.duplicate(true),
		"world_state": world_state.duplicate(true),
		"started_at_msec": started_at_msec,
	}

func restore_from_save_data(data: Dictionary) -> void:
	is_run_active = bool(data.get("is_run_active", false))
	current_sea_id = data.get("current_sea_id", "")
	current_stage_id = data.get("current_stage_id", "")
	current_stage_index = int(data.get("current_stage_index", 0))
	active_upgrades = _to_string_array(data.get("active_upgrades", []))
	pending_rewards = _to_upgrade_id_array(data.get("pending_rewards", []))
	difficulty = float(data.get("difficulty", 1.0))
	currency = data.get("currency", {"gold": 0, "scrap": 0})
	var player_state_value: Variant = data.get("player_ship_state", {})
	player_ship_state = (
		(player_state_value as Dictionary).duplicate(true)
		if player_state_value is Dictionary else {}
	)
	selected_player_ship_id = _validated_ship_id(str(
		data.get(
			"selected_player_ship_id",
			player_ship_state.get(
				"ship_id",
				GameConfig.DEFAULT_PLAYER_SHIP_ID
			)
		)
	))
	player_ship_state["ship_id"] = selected_player_ship_id
	var carrier_states_value: Variant = data.get(
		"carrier_air_group_states",
		{}
	)
	carrier_air_group_states = (
		carrier_states_value as Dictionary
	).duplicate(true) if carrier_states_value is Dictionary else {}
	world_state = data.get("world_state", {})
	started_at_msec = int(data.get("started_at_msec", 0))
	_emit_updated()

func save_current_run() -> Error:
	if not has_node("/root/SaveManager"):
		return ERR_UNAVAILABLE
	return get_node("/root/SaveManager").save_run(to_save_data())

func load_saved_run() -> bool:
	if not has_node("/root/SaveManager"):
		return false
	var save_manager = get_node("/root/SaveManager")
	if not save_manager.run_exists():
		return false
	restore_from_save_data(save_manager.load_run())
	return is_run_active

func clear_saved_run() -> Error:
	if not has_node("/root/SaveManager"):
		return ERR_UNAVAILABLE
	return get_node("/root/SaveManager").delete_run()

func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result

func _to_upgrade_id_array(value) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item in value:
		if item is String:
			if not item.is_empty():
				result.append(item)
		elif item is UpgradeData:
			if not item.id.is_empty():
				result.append(item.id)
		elif item is Dictionary:
			var upgrade_id := str(item.get("id", ""))
			if not upgrade_id.is_empty():
				result.append(upgrade_id)
	return result

func _vector3_to_dictionary(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}


func _get_carrier_key(carrier: ShipUnit) -> String:
	if carrier.player_controlled:
		return PLAYER_CARRIER_KEY
	return "%s:%s:%s" % [
		carrier.ship_id,
		String(carrier.fleet_id),
		carrier.name,
	]


func get_selected_player_ship_id() -> String:
	return selected_player_ship_id


func _validated_ship_id(ship_id: String) -> String:
	if ShipDatabase.SHIP_PATHS.has(ship_id):
		return ship_id
	if not ship_id.is_empty():
		push_warning(
			"Unsupported player ship id '%s'; using '%s'."
			% [ship_id, GameConfig.DEFAULT_PLAYER_SHIP_ID]
		)
	return GameConfig.DEFAULT_PLAYER_SHIP_ID

func _emit_started() -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").run_started.emit(current_stage_id)

func _emit_updated() -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").run_updated.emit(to_save_data())
