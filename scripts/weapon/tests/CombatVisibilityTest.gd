extends SceneTree

const WEAPON_STAGE: StageData = preload(
	"res://resources/stages/tests/weapon_combat_test.tres"
)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var packed := load("res://scenes/world/battle_scene.tscn") as PackedScene
	_check(packed != null, "battle scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as BattleScene
	scene.stage_override = WEAPON_STAGE
	root.add_child(scene)
	await process_frame
	await physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED

	var player := scene.player_ship as ShipUnit
	_check(player != null, "player ship exists")
	if player != null:
		var destroyer := _find_ship_by_id(
			scene.get_battle_units(),
			"dd_bluewind"
		)
		_test_ballistic_configuration(player)
		_test_maximum_range_pitch(player)
		_test_impact_marker(scene, player)
		_test_cannon_range_preview(scene, player)
		_test_shell_trail(scene, player)
		_check(destroyer != null, "battle contains a destroyer")
		if destroyer != null:
			_test_torpedo_visibility(scene, destroyer)
			_test_ship_wake_scaling(scene, destroyer)

	scene.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null:
		object_pool.clear_pool()
	_finish()


func _test_impact_marker(scene: BattleScene, player: ShipUnit) -> void:
	player.combat.set_aim_point(
		player.global_position + Vector3(0.0, 0.0, -5000.0)
	)
	for cannon in player.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	):
		cannon.call(&"_turn_toward", player.combat.aim_point, 1.0)
	scene.call(&"_update_impact_marker")
	var marker := scene.get_node_or_null("ImpactMarker") as MeshInstance3D
	var torus := marker.mesh as TorusMesh if marker != null else null
	_check(marker != null and marker.visible, "predicted impact marker is visible")
	_check(
		torus != null and torus.outer_radius >= 50.0,
		"impact marker is large enough for the RTS camera"
	)


func _test_ballistic_configuration(player: ShipUnit) -> void:
	var shell_scene := load(
		"res://scenes/weapon/projectiles/shell_projectile.tscn"
	) as PackedScene
	var shell_node := shell_scene.instantiate() \
		if shell_scene != null else null
	_check(
		shell_node is ShellProjectile and shell_node.get_class() == "Node3D",
		"combat shell uses direct Node3D simulation instead of Jolt velocity"
	)
	if shell_node != null:
		shell_node.free()
	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var weapon_database := WeaponDatabase.new()
	for weapon_id in [
		"destroyer_cannon",
		"cruiser_cannon",
		"battleship_cannon",
		"carrier_secondary",
	]:
		var weapon := weapon_database.find_weapon(weapon_id)
		var shell_data := weapon.projectile_data as ShellProjectileData \
			if weapon != null else null
		var expected_velocity := sqrt(weapon.range_meters * gravity) \
			if weapon != null else 0.0
		_check(
			weapon != null
				and absf(weapon.muzzle_velocity - expected_velocity) <= 1.0,
			"%s reaches nominal range near 45 degrees" % weapon_id
		)
		_check(
			shell_data != null
				and is_equal_approx(
					shell_data.muzzle_velocity,
					weapon.muzzle_velocity
				)
				and shell_data.gravity_scale == 1.0
				and shell_data.mass_kg > 1.0,
			"%s shell data matches immutable ballistic configuration" % weapon_id
		)
		_check(
			shell_data != null
				and shell_data.lifetime_seconds
					>= (sqrt(2.0) * weapon.muzzle_velocity / gravity) * 1.1,
			"%s shell lifetime covers its maximum-range flight" % weapon_id
		)
	for cannon in player.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	):
		var expected_velocity := sqrt(cannon.get_range_m() * gravity)
		var actual_velocity := cannon.get_muzzle_velocity_vector().length()
		_check(
			absf(actual_velocity - expected_velocity) <= 1.0,
			"cannon maximum range corresponds to an approximately 45 degree shot"
		)


func _test_cannon_range_preview(
		scene: BattleScene,
		player: ShipUnit
) -> void:
	var preview := scene.ship_aim_range_preview
	_check(preview != null, "battle includes a cannon range preview")
	if preview == null:
		return
	scene.input_manager.ship_command_controller.set_aim_point(
		player.global_position + Vector3(0.0, 0.0, -3000.0)
	)
	preview.call(&"_process", 0.0)
	var preview_mesh := preview.line_mesh.mesh as BoxMesh
	var maximum_range := player \
		.get_selected_cannon_maximum_range_m()
	_check(
		preview.visible
			and preview_mesh != null
			and is_equal_approx(
				preview.line_mesh.scale.z,
				maximum_range
			),
		"solid cannon aim line uses the runtime maximum range"
	)


func _test_maximum_range_pitch(player: ShipUnit) -> void:
	var cannons := player.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)
	_check(not cannons.is_empty(), "player has a cannon for ballistic pitch validation")
	if cannons.is_empty():
		return
	var cannon := cannons[0] as CannonMount
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	var aim_point := cannon.get_muzzle_position() \
		+ forward.normalized() * cannon.get_range_m()
	cannon.aim_at(aim_point)
	cannon.call(&"_turn_toward", aim_point, 10.0)
	_check(
		cannon.pitch_degrees >= 43.0 and cannon.pitch_degrees <= 46.0,
		"nominal maximum range produces an approximately 45 degree gun angle"
	)


func _test_shell_trail(scene: BattleScene, player: ShipUnit) -> void:
	var cannons := player.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)
	_check(not cannons.is_empty(), "player has a cannon")
	if cannons.is_empty():
		return
	var cannon := cannons[0]
	var aim_point := player.global_position + Vector3(0.0, 0.0, -3000.0)
	cannon.aim_at(aim_point)
	cannon.call(&"_turn_toward", aim_point, 10.0)
	var fired := cannon.fire()
	_check(fired, "cannon fires for trail validation")
	var projectile := _find_shell_from_ship(
		scene.get_node_or_null("Projectiles"),
		player.get_instance_id()
	)
	var trail := projectile.get_node_or_null("TrailParticles") \
		as GPUParticles3D if projectile != null else null
	var shell_data := cannon.weapon_data.projectile_data \
		as ShellProjectileData
	_check(
		trail != null and trail.emitting and trail.lifetime >= 1.0,
		"shell emits a persistent visual trail"
	)
	_check(
		projectile != null
			and shell_data != null
			and is_equal_approx(projectile.mass, shell_data.mass_kg),
		"spawned shell retains configured mass as damage/visual data"
	)
	if projectile != null:
		projectile.despawn()


func _test_torpedo_visibility(scene: BattleScene, player: ShipUnit) -> void:
	var mount := player.weapon_mount_root.get_node_or_null("center_port") \
		as TorpedoMount
	_check(mount != null, "player has a port torpedo mount")
	if mount == null:
		return
	var aim_point := mount.global_position \
		+ -mount.global_transform.basis.z.normalized() * 1200.0
	aim_point.y = player.global_position.y
	mount.aim_at(aim_point)
	mount.update_traverse_toward(
		aim_point,
		mount.yaw_speed_degrees,
		1.0
	)
	_check(mount.fire(), "torpedo mount fires for wake validation")
	var torpedo := _find_torpedo_from_ship(
		scene.get_node_or_null("Projectiles"),
		player.get_instance_id()
	)
	var wake := torpedo.get_node_or_null("WakeParticles") \
		as GPUParticles3D if torpedo != null else null
	var visual_mesh := torpedo.get_node_or_null("Mesh") \
		as MeshInstance3D if torpedo != null else null
	var capsule := visual_mesh.mesh as CapsuleMesh if visual_mesh != null else null
	_check(
		capsule != null and capsule.radius >= 0.75 and capsule.height >= 5.0,
		"torpedo visual mesh is enlarged without changing collision data"
	)
	_check(
		wake != null and wake.emitting and wake.lifetime >= 5.0,
		"torpedo emits a long surface wake"
	)
	if torpedo != null:
		torpedo.despawn()


func _test_ship_wake_scaling(scene: BattleScene, player: ShipUnit) -> void:
	var battleship := _find_ship_by_id(scene.enemies, "bb_ironwake")
	_check(battleship != null, "enemy battleship exists")
	if battleship == null:
		return
	var destroyer_wake := player.get_node_or_null("ShipWakeEmitter") \
		as ShipWakeEmitter
	var battleship_wake := battleship.get_node_or_null("ShipWakeEmitter") \
		as ShipWakeEmitter
	_check(
		destroyer_wake != null and battleship_wake != null,
		"ships include wake emitters"
	)
	if destroyer_wake == null or battleship_wake == null:
		return
	player.movement.current_speed_mps = player.ship_data.max_speed_mps * 0.65
	battleship.movement.current_speed_mps = \
		battleship.ship_data.max_speed_mps * 0.65
	destroyer_wake.call(&"_process", 0.1)
	battleship_wake.call(&"_process", 0.1)
	var destroyer_plane := destroyer_wake.draw_pass_1 as PlaneMesh
	var battleship_plane := battleship_wake.draw_pass_1 as PlaneMesh
	_check(
		destroyer_wake.emitting and battleship_wake.emitting,
		"moving ships emit wakes"
	)
	_check(
		battleship_wake.amount > destroyer_wake.amount
			and battleship_plane.size.x > destroyer_plane.size.x,
		"wake density and width scale with hull size"
	)


func _find_shell_from_ship(parent: Node, source_id: int) -> Projectile:
	if parent == null:
		return null
	for child in parent.get_children():
		var projectile := child as Projectile
		if projectile != null and projectile.source_ship_instance_id == source_id:
			return projectile
	return null


func _find_torpedo_from_ship(
		parent: Node,
		source_id: int
) -> TorpedoProjectile:
	if parent == null:
		return null
	for child in parent.get_children():
		var torpedo := child as TorpedoProjectile
		if torpedo != null and torpedo.source_ship_instance_id == source_id:
			return torpedo
	return null


func _find_ship_by_id(ships: Array, ship_id: String) -> ShipUnit:
	for value in ships:
		var ship := value as ShipUnit
		if ship != null and ship.ship_id == ship_id:
			return ship
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	for failure in _failures:
		push_error("COMBAT VISIBILITY TEST: %s" % failure)
	if _failures.is_empty():
		print("COMBAT_VISIBILITY_TEST PASS")
	quit(0 if _failures.is_empty() else 1)
