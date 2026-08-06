extends RefCounted
class_name CombatIdentity
## Stable value identities for deterministic gameplay decisions.
##
## Runtime instance ids remain valid dictionary keys and lifetime guards, but
## they must not influence gameplay RNG because allocation order is not stable.


## Ship ids fall back to ship_id+team when no stage spawn id was assigned.
## That fallback is stable across runs but NOT unique for duplicate hulls of
## one team, so gameplay spawns must always carry a combat_spawn_id; the
## debug warning below surfaces any real path that reaches the fallback.
static var _warned_fallback_ship_ids := {}


static func for_ship(ship: ShipUnit) -> int:
	if ship == null or not is_instance_valid(ship):
		return 0
	if ship.combat_spawn_id != 0:
		return ship.combat_spawn_id
	if OS.is_debug_build():
		var warn_key := "%s/%s" % [ship.ship_id, ship.team]
		if not _warned_fallback_ship_ids.has(warn_key):
			_warned_fallback_ship_ids[warn_key] = true
			push_warning(
				"Unstable CombatIdentity fallback used for gameplay RNG: "
				+ "ship '%s' (team %s) has no combat_spawn_id"
				% [ship.ship_id, ship.team]
			)
	return _nonzero_hash([
		&"ship",
		StringName(ship.ship_id),
		ship.team,
	])


static func for_stage_spawn(
		stage_id: StringName,
		spawn_role: StringName,
		spawn_index: int
) -> int:
	return _nonzero_hash([
		&"stage_ship",
		stage_id,
		spawn_role,
		maxi(spawn_index, 0),
	])


static func for_squadron(squadron: AircraftSquadron) -> int:
	if squadron == null or not is_instance_valid(squadron):
		return 0
	var squadron_id := StringName(squadron.squadron_data.id) \
		if squadron.squadron_data != null else &"unknown_squadron"
	return _nonzero_hash([
		&"squadron",
		for_ship(squadron.get_owner_carrier()),
		squadron_id,
		squadron.get_team(),
	])


static func for_aircraft(
		squadron: AircraftSquadron,
		slot_id: int
) -> int:
	return _nonzero_hash([
		&"aircraft",
		for_squadron(squadron),
		maxi(slot_id, 0),
	])


static func for_mount(owner_ship: ShipUnit, mount: CannonMount) -> int:
	if mount == null or not is_instance_valid(mount):
		return 0
	var slot_id := mount.slot_data.slot_id \
		if mount.slot_data != null else StringName(mount.name)
	return _nonzero_hash([
		&"mount",
		for_ship(owner_ship),
		slot_id,
	])


static func for_world_position(position: Vector3) -> int:
	return _nonzero_hash([
		&"world_position",
		int(round(position.x * 10.0)),
		int(round(position.y * 10.0)),
		int(round(position.z * 10.0)),
	])


static func _nonzero_hash(parts: Array) -> int:
	var value := hash(parts)
	return value if value != 0 else 1
