extends RefCounted
class_name ThreatMemory

var half_life_sec := 12.0
var minimum_retained_threat := 0.05
var _entries: Dictionary = {}


func register_damage(
		attacker: Node,
		damage: float,
		damage_to_owner: bool,
		damage_info: Dictionary = {},
		now_sec: float = -1.0,
		damaged_max_health: float = 0.0
) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var resolved_now := _resolve_now_sec(now_sec)
	var attacker_id := attacker.get_instance_id()
	var entry := _get_or_create_entry(attacker, resolved_now)
	_decay_entry(entry, resolved_now)
	if damage_to_owner:
		entry["damage_to_owner"] = float(entry["damage_to_owner"]) + maxf(damage, 0.0)
	else:
		entry["damage_to_allies"] = float(entry["damage_to_allies"]) + maxf(damage, 0.0)
		entry["damage_to_allies_ratio"] = float(entry["damage_to_allies_ratio"]) \
			+ maxf(damage, 0.0) / maxf(damaged_max_health, 1.0)
	entry["last_damage_sec"] = resolved_now
	entry["last_seen_sec"] = resolved_now
	entry["source_ship_instance_id"] = int(
		damage_info.get("source_ship_instance_id", attacker_id)
	)
	entry["weapon_id"] = StringName(str(damage_info.get("weapon_id", "")))
	entry["projectile_type"] = StringName(str(damage_info.get("projectile_type", "")))
	_entries[attacker_id] = entry


func record_detection(candidate: Node, now_sec: float = -1.0) -> void:
	if candidate == null or not is_instance_valid(candidate):
		return
	var resolved_now := _resolve_now_sec(now_sec)
	var entry := _get_or_create_entry(candidate, resolved_now)
	_decay_entry(entry, resolved_now)
	entry["last_seen_sec"] = resolved_now
	_entries[candidate.get_instance_id()] = entry


func get_snapshot(candidate: Node, now_sec: float = -1.0) -> Dictionary:
	if candidate == null or not is_instance_valid(candidate):
		return _empty_snapshot()
	var candidate_id := candidate.get_instance_id()
	if not _entries.has(candidate_id):
		return _empty_snapshot()
	var resolved_now := _resolve_now_sec(now_sec)
	var entry: Dictionary = _entries[candidate_id]
	_decay_entry(entry, resolved_now)
	_entries[candidate_id] = entry
	return {
		"damage_to_owner": float(entry["damage_to_owner"]),
		"damage_to_allies": float(entry["damage_to_allies"]),
		"damage_to_allies_ratio": float(entry["damage_to_allies_ratio"]),
		"last_damage_sec": float(entry["last_damage_sec"]),
		"last_seen_sec": float(entry["last_seen_sec"]),
		"source_ship_instance_id": int(entry["source_ship_instance_id"]),
		"weapon_id": entry["weapon_id"],
		"projectile_type": entry["projectile_type"],
	}


func cleanup(now_sec: float = -1.0) -> void:
	var resolved_now := _resolve_now_sec(now_sec)
	for attacker_id in _entries.keys():
		var entry: Dictionary = _entries[attacker_id]
		var attacker_ref := entry.get("attacker_ref") as WeakRef
		var attacker: Object = attacker_ref.get_ref() if attacker_ref != null else null
		_decay_entry(entry, resolved_now)
		var total_threat := float(entry["damage_to_owner"]) \
			+ float(entry["damage_to_allies"])
		if attacker == null or not is_instance_valid(attacker) \
				or total_threat < minimum_retained_threat:
			_entries.erase(attacker_id)
		else:
			_entries[attacker_id] = entry


func get_entry_count() -> int:
	return _entries.size()


func get_tracked_ships() -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for entry_value in _entries.values():
		var entry := entry_value as Dictionary
		var attacker_ref := entry.get("attacker_ref") as WeakRef
		var attacker := attacker_ref.get_ref() as ShipUnit \
			if attacker_ref != null else null
		if attacker != null and is_instance_valid(attacker) and attacker.is_alive():
			result.append(attacker)
	return result


func _get_or_create_entry(attacker: Node, now_sec: float) -> Dictionary:
	var attacker_id := attacker.get_instance_id()
	if _entries.has(attacker_id):
		return _entries[attacker_id]
	return {
		"attacker_ref": weakref(attacker),
		"damage_to_owner": 0.0,
		"damage_to_allies": 0.0,
		"damage_to_allies_ratio": 0.0,
		"last_damage_sec": -INF,
		"last_seen_sec": now_sec,
		"last_update_sec": now_sec,
		"source_ship_instance_id": attacker_id,
		"weapon_id": StringName(),
		"projectile_type": StringName(),
	}


func _decay_entry(entry: Dictionary, now_sec: float) -> void:
	var elapsed_sec := maxf(now_sec - float(entry["last_update_sec"]), 0.0)
	if elapsed_sec <= 0.0:
		return
	var decay_multiplier := pow(0.5, elapsed_sec / maxf(half_life_sec, 0.01))
	entry["damage_to_owner"] = float(entry["damage_to_owner"]) * decay_multiplier
	entry["damage_to_allies"] = float(entry["damage_to_allies"]) * decay_multiplier
	entry["damage_to_allies_ratio"] = float(entry["damage_to_allies_ratio"]) * decay_multiplier
	entry["last_update_sec"] = now_sec


func _empty_snapshot() -> Dictionary:
	return {
		"damage_to_owner": 0.0,
		"damage_to_allies": 0.0,
		"damage_to_allies_ratio": 0.0,
		"last_damage_sec": -INF,
		"last_seen_sec": -INF,
		"source_ship_instance_id": 0,
		"weapon_id": StringName(),
		"projectile_type": StringName(),
	}


func _resolve_now_sec(value: float) -> float:
	return value if value >= 0.0 else float(Time.get_ticks_msec()) * 0.001
