extends SceneTree

const DEFAULT_SIMULATION_FRAMES := 36000

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var simulation_frames := _resolve_simulation_frames()
	var simulation_seed := _resolve_seed()
	seed(simulation_seed)
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	if packed == null:
		push_error("AI LONG RUN: battle scene failed to load")
		quit(1)
		return
	var scene := packed.instantiate() as BattleScene
	root.add_child(scene)
	await process_frame
	await physics_frame

	for _frame in simulation_frames:
		await physics_frame

	var live_units := scene.get_battle_units()
	var max_target_evaluations := 0
	var max_pursuit_updates := 0
	var max_path_calculations := 0
	for unit_value in live_units:
		var unit := unit_value as ShipUnit
		if unit == null or unit.player_controlled:
			continue
		max_target_evaluations = maxi(
			max_target_evaluations,
			unit.targeting.target_evaluation_count
		)
		max_pursuit_updates = maxi(
			max_pursuit_updates,
			unit.ai.pursuit_navigation_update_count
		)
		max_path_calculations = maxi(
			max_path_calculations,
			unit.navigation.path_calculation_count
		)
		if unit.get_ai_target() != unit.ai.target or unit.get_ai_target() != unit.combat.target:
			_failures.append("%s has inconsistent targeting component, AI, and combat targets" % unit.name)

	if max_target_evaluations > 800:
		_failures.append("target evaluation exceeded the expected staggered ~1 Hz budget")
	if max_pursuit_updates > 2100:
		_failures.append("pursuit navigation updates exceeded the 0.3 s emergency ceiling")
	if max_path_calculations > 2100:
		_failures.append("navigation path calculations exceeded the 0.3 s emergency ceiling")

	print(
		"AI_LONG_RUN frames=%d live_units=%d max_evaluations=%d max_pursuit_updates=%d max_path_calculations=%d failures=%d" % [
			simulation_frames,
			live_units.size(),
			max_target_evaluations,
			max_pursuit_updates,
			max_path_calculations,
			_failures.size(),
		]
	)
	for failure in _failures:
		push_error("AI LONG RUN: %s" % failure)

	if root.has_node("ObjectPool"):
		root.get_node("ObjectPool").call(&"clear_pool")
	scene.queue_free()
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _resolve_simulation_frames() -> int:
	var override := OS.get_environment("NAVYBLUE_LONG_RUN_FRAMES")
	return maxi(int(override), 1) \
		if override.is_valid_int() else DEFAULT_SIMULATION_FRAMES


func _resolve_seed() -> int:
	var override := OS.get_environment("NAVYBLUE_ENDURANCE_SEED")
	return int(override) if override.is_valid_int() else 1
