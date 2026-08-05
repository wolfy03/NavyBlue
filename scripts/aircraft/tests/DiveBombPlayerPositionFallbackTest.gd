extends SceneTree
## Player designation on empty water (no hostile ship inside the radius):
## the run attacks the designated position itself with zero target velocity.

const BATTLE_SCENE := preload("res://scenes/world/battle_scene.tscn")
const STAGE: StageData = preload(
	"res://resources/stages/tests/carrier_player_test.tres"
)

var _failures: Array[String] = []
var _released_projectiles: Array[WeakRef] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var battle := BATTLE_SCENE.instantiate() as BattleScene
	battle.stage_override = STAGE
	root.add_child(battle)
	await physics_frame
	var carrier := battle.player_ship as ShipUnit
	var squadron := carrier.carrier_air_group.launch_manual_squadron(
		"basic_bomber_squadron"
	)
	_check(squadron != null, "squadron launches")
	if squadron == null:
		await _finish(battle)
		return
	squadron.set_physics_process(false)
	for aircraft in squadron.aircraft_units:
		aircraft.activate()
		aircraft.set_physics_process(false)
		aircraft.weapon_controller.weapon_released.connect(
			_on_weapon_released
		)
	# Inside the squadron's combat radius but far from every stage ship:
	# nothing inside the 250 m acquisition radius.
	var designation := carrier.global_position + Vector3(1500.0, 0.0, -1500.0)
	designation.y = 0.0
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship == null:
			continue
		var offset := ship.global_position - designation
		offset.y = 0.0
		_check(
			offset.length() > 250.0,
			"precondition: no ship inside the acquisition radius"
		)
	_check(
		squadron.issue_player_move_command(Vector3.ZERO, null),
		"player takes command"
	)
	var targeting_session := battle.dive_bomb_targeting_session
	var target_preview := battle.dive_bomb_target_preview
	_check(
		targeting_session != null and target_preview != null,
		"battle composes dive targeting and preview"
	)
	var commands: Array[DiveBombCommand] = []
	if targeting_session != null and target_preview != null:
		var selected: Array[AircraftSquadron] = [squadron]
		_check(
			targeting_session.begin(selected, designation),
			"manual dive targeting starts"
		)
		await process_frame
		_check(target_preview.visible, "manual dive preview is visible")
		var preview_aabb := target_preview._ring.mesh.get_aabb() \
			if target_preview._ring != null \
			and target_preview._ring.mesh != null else AABB()
		_check(
			preview_aabb.size.x >= target_preview.minimum_visible_radius_m * 2.0,
			"perfect accuracy still draws a visible preview footprint"
		)
		commands = targeting_session.confirm(designation, null)
	_check(commands.size() == 1, "empty-water click creates one typed command")
	var command := commands[0] if not commands.is_empty() else null
	_check(
		command != null and squadron.begin_manual_dive_at(
			command.target_point,
			command.dispersion_radius_m,
			command.get_target_ship()
		),
		"empty-water command starts a player dive run"
	)
	var run := squadron._player_dive_run
	var resolved := run.get_resolved_target() if run != null else null
	_check(
		resolved != null \
			and resolved.type \
				== DiveBombResolvedTarget.TargetType.WORLD_POSITION,
		"no ship in the radius falls back to the position"
	)
	_check(
		resolved != null \
			and resolved.get_aim_position() == designation \
			and resolved.get_target_velocity() == Vector3.ZERO,
		"the fallback aims at the designation with zero velocity"
	)
	if run != null:
		run.update(0.0)
		var entry := squadron.destination
		var to_designation := entry - designation
		to_designation.y = 0.0
		_check(
			to_designation.length() < 1500.0,
			"the entry waypoint is planned around the designated point"
		)
	# The old assertion stopped at command construction. Run the real squadron
	# and projectile lifecycle so an empty-water order cannot silently stall
	# before release.
	for aircraft in squadron.aircraft_units:
		aircraft.set_physics_process(true)
	squadron.set_physics_process(true)
	var impact_position := Vector3.INF
	var observed_projectile: Projectile
	for _frame in 3600:
		await physics_frame
		if observed_projectile == null:
			observed_projectile = _get_first_projectile()
		if observed_projectile != null \
				and is_instance_valid(observed_projectile) \
				and not observed_projectile.active:
			impact_position = observed_projectile.last_despawn_position
			break
	_check(
		impact_position.is_finite(),
		"empty-water order releases and resolves a real bomb projectile"
	)
	if impact_position.is_finite():
		var horizontal_error := impact_position - designation
		horizontal_error.y = 0.0
		_check(
			horizontal_error.length() <= 75.0,
			"empty-water bomb impacts the designated position"
		)
	await _finish(battle)


func _get_first_projectile() -> Projectile:
	for reference in _released_projectiles:
		var value: Variant = reference.get_ref()
		if value != null and is_instance_valid(value) and value is Projectile:
			return value as Projectile
	return null


func _on_weapon_released(_aircraft: AircraftUnit, projectile: Node) -> void:
	if projectile != null:
		_released_projectiles.append(weakref(projectile))


func _finish(battle: BattleScene) -> void:
	battle.queue_free()
	await process_frame
	for failure in _failures:
		push_error("PLAYER POSITION FALLBACK: %s" % failure)
	print(
		"DIVE_BOMB_PLAYER_POSITION_FALLBACK_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
