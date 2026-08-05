extends SceneTree

const DIVE_DATA: DiveBomberCombatData = preload(
	"res://resources/aircraft/dive_bomber/basic_dive_bomber_combat.tres"
)
const WEAPON_DATA: AircraftWeaponData = preload(
	"res://resources/aircraft/weapons/basic_bomb_loadout.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var first := AircraftUnit.new()
	var second := AircraftUnit.new()
	root.add_child(first)
	root.add_child(second)
	await process_frame
	first.global_position = Vector3(-80.0, 350.0, -900.0)
	second.global_position = Vector3(95.0, 350.0, -830.0)
	var final_aim := Vector3(500.0, 0.0, 700.0)
	var context := DiveBombAttackContext.new()
	var first_solution := DiveBombAttackPlanner.build_fixed_impact_solution(
		first,
		final_aim,
		Vector3(12.0, 0.0, 0.0),
		DIVE_DATA,
		WEAPON_DATA,
		context
	)
	var second_solution := DiveBombAttackPlanner.build_fixed_impact_solution(
		second,
		final_aim,
		Vector3(12.0, 0.0, 0.0),
		DIVE_DATA,
		WEAPON_DATA,
		context
	)
	_check(first_solution != null and first_solution.valid, "first solve valid")
	_check(second_solution != null and second_solution.valid, "second solve valid")
	if first_solution != null and second_solution != null:
		_check(
			first_solution.final_aim_impact_position.is_equal_approx(final_aim)
				and second_solution.final_aim_impact_position.is_equal_approx(
					final_aim
				),
			"all aircraft share the pass final aim"
		)
		_check(
			not first_solution.release_position.is_equal_approx(
				second_solution.release_position
			),
			"aircraft positions produce independent release points"
		)
		_check(
			not first_solution.attack_direction.is_equal_approx(
				second_solution.attack_direction
			),
			"aircraft positions produce independent locked headings"
		)
	first.queue_free()
	second.queue_free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	print(
		"DIVE_BOMB_INDIVIDUAL_AIRCRAFT_SOLUTION_TEST failures=%d"
		% _failures.size()
	)
	for failure in _failures:
		push_error("DIVE SOLUTION: %s" % failure)
	quit(0 if _failures.is_empty() else 1)
