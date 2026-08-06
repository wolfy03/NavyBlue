extends SceneTree
## Combat identity contract (§30-32): ids are pure functions of stable
## spawn/slot data - never of Object allocation order - so the deterministic
## RNG they seed (gunnery observation phase, dive-bomb dispersion) is
## reproducible across runs and save restores.

const SHIP_SCENE := preload("res://scenes/unit/ship.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var holder := Node.new()
	root.add_child(holder)

	# --- Two instantiation orders, same spawn ids: identical identities.
	var first_pass := _spawn_ships_with_ids(holder, [101, 202])
	var first_ids: Array[int] = []
	for ship in first_pass:
		first_ids.append(CombatIdentity.for_ship(ship))
	for ship in first_pass:
		ship.queue_free()
	await process_frame
	var second_pass := _spawn_ships_with_ids(holder, [202, 101])
	var second_ids: Array[int] = []
	for ship in second_pass:
		second_ids.append(CombatIdentity.for_ship(ship))
	# Both passes are sorted by spawn id, so equal indexes must yield equal
	# identities even though the two passes instantiated in opposite order.
	_check(
		first_ids[0] == second_ids[0] and first_ids[1] == second_ids[1],
		"ship identity depends on the spawn id, not allocation order"
	)
	_check(
		first_ids[0] != first_ids[1],
		"different spawns get different identities"
	)

	# --- Stage spawn identity is a pure function of its inputs.
	_check(
		CombatIdentity.for_stage_spawn(&"stage_3", &"escort", 2) \
			== CombatIdentity.for_stage_spawn(&"stage_3", &"escort", 2),
		"stage spawn identity is deterministic"
	)
	_check(
		CombatIdentity.for_stage_spawn(&"stage_3", &"escort", 2) \
			!= CombatIdentity.for_stage_spawn(&"stage_3", &"escort", 3),
		"stage spawn identity distinguishes spawn indexes"
	)

	# --- The gunnery observation phase seed derives from the identity, so
	# equal setups produce equal seeds regardless of instance ids.
	var seed_a: int = CombatIdentity.for_ship(second_pass[0]) \
		* 1103515245 + 12345
	var seed_b: int = first_ids[0] * 1103515245 + 12345
	_check(
		seed_a == seed_b,
		"observation noise seeds survive re-instantiation"
	)

	# --- The gameplay seed source contains no raw instance-id hash.
	var threat_source := FileAccess.get_file_as_string(
		"res://scripts/ai/ThreatTargetingComponent.gd"
	)
	_check(
		not threat_source.contains("owner_ship.get_instance_id()"),
		"threat targeting no longer seeds from the instance id"
	)
	for ship in second_pass:
		ship.queue_free()
	holder.queue_free()
	await process_frame
	for failure in _failures:
		push_error("COMBAT IDENTITY STABILITY: %s" % failure)
	print(
		"COMBAT_IDENTITY_STABILITY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _spawn_ships_with_ids(
		parent: Node,
		spawn_ids: Array
) -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for spawn_id in spawn_ids:
		var ship := SHIP_SCENE.instantiate() as ShipUnit
		ship.team = &"enemy"
		ship.combat_spawn_id = int(spawn_id)
		parent.add_child(ship)
		ship.set_physics_process(false)
		result.append(ship)
	# Return sorted by spawn id so callers can index deterministically.
	result.sort_custom(
		func(left: ShipUnit, right: ShipUnit) -> bool:
			return left.combat_spawn_id < right.combat_spawn_id
	)
	return result


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
