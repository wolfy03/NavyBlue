extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleTestServices.create(self)
	var carrier_scene := load("res://scenes/unit/ship.tscn") as PackedScene
	var carrier := carrier_scene.instantiate() as ShipUnit
	carrier.team = FactionRelations.PLAYER
	carrier.player_controlled = true
	root.add_child(carrier)
	var aircraft_root := Node3D.new()
	aircraft_root.add_to_group(&"aircraft_root")
	root.add_child(aircraft_root)
	var projectile_root := Node3D.new()
	projectile_root.add_to_group(&"projectile_root")
	root.add_child(projectile_root)
	var squadron_scene := load(
		"res://scenes/aircraft/aircraft_squadron.tscn"
	) as PackedScene
	var squadron := squadron_scene.instantiate() as AircraftSquadron
	root.add_child(squadron)
	var squadron_data := load(
		"res://resources/aircraft/squadrons/basic_torpedo_squadron.tres"
	) as SquadronData
	squadron.setup(carrier, squadron_data, aircraft_root, 1, services)
	squadron.launch_to(Vector3(0.0, 180.0, 500.0))
	squadron.set_command_authority(AircraftSquadron.CommandAuthority.PLAYER)
	var alive := squadron.get_alive_aircraft()
	_check(alive.size() == 1, "one aircraft is active for the sortie")
	var aircraft := alive[0] if not alive.is_empty() else null
	if aircraft != null:
		aircraft.global_transform = Transform3D(
			Basis.IDENTITY,
			Vector3(0.0, 25.0, 0.0)
		)
		aircraft.velocity = Vector3(0.0, 0.0, -65.0)
	var command := TorpedoAttackCommand.new()
	command.command_id = 41
	command.entry_point = Vector3(0.0, 0.0, 700.0)
	command.requested_release_point = Vector3.ZERO
	command.actual_release_point = Vector3.ZERO
	command.approach_point = Vector3(0.0, 0.0, 1200.0)
	command.escape_point = Vector3(0.0, 0.0, -650.0)
	command.attack_direction = Vector3.FORWARD
	command.requested_run_distance_m = 700.0
	command.actual_run_distance_m = 700.0
	command.minimum_run_distance_m = 700.0
	command.command_plane_height_m = 0.0
	_check(
		squadron.issue_player_torpedo_attack(command),
		"typed player torpedo command starts"
	)
	var controller := squadron.torpedo_attack_controller
	controller.state = TorpedoAttackController.State.RELEASING
	controller.update_attack(0.0)
	_check(
		controller.get_released_aircraft_count() == 1,
		"one live armed aircraft releases one torpedo"
	)
	_check(
		aircraft != null \
			and aircraft.weapon_controller.get_remaining_ammunition() == 0,
		"payload is consumed after projectile creation"
	)
	_check(
		projectile_root.get_child_count() == 1 \
			and projectile_root.get_child(0) is TorpedoProjectile,
		"release creates a typed torpedo projectile"
	)
	var torpedo := projectile_root.get_child(0) as TorpedoProjectile \
		if projectile_root.get_child_count() > 0 else null
	_check(
		torpedo != null \
			and torpedo.launch_phase \
				== TorpedoProjectile.LaunchPhase.AIRBORNE,
		"aircraft release enters the airborne lifecycle"
	)
	controller.update_attack(0.0)
	_check(
		projectile_root.get_child_count() == 1,
		"resolved aircraft cannot release a duplicate torpedo"
	)
	squadron.shutdown()
	for child in projectile_root.get_children():
		var projectile := child as WeaponProjectileBase
		if projectile != null:
			projectile.recycle_projectile()
	squadron.queue_free()
	aircraft_root.queue_free()
	projectile_root.queue_free()
	carrier.queue_free()
	await process_frame
	var object_pool := root.get_node_or_null("ObjectPool")
	if object_pool != null and object_pool.has_method(&"clear_pool"):
		object_pool.call(&"clear_pool")
	await process_frame
	await process_frame
	print(
		"TORPEDO_ATTACK_PER_AIRCRAFT_RELEASE_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("TORPEDO RELEASE: %s" % label)
