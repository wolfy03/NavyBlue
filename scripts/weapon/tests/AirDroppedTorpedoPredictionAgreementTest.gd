extends SceneTree

const TORPEDO_SCENE := preload(
	"res://scenes/weapon/projectiles/torpedo_projectile.tscn"
)

var _failures := PackedStringArray()
var _predicted_distance_m := 0.0
var _actual_distance_m := 0.0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleTestServices.create(self)
	var torpedo := TORPEDO_SCENE.instantiate() as TorpedoProjectile
	root.add_child(torpedo)
	var data := load(
		"res://resources/projectiles/aircraft_torpedo.tres"
	) as TorpedoProjectileData
	var context := ProjectileLaunchContext.new()
	context.source_team = FactionRelations.PLAYER
	context.source_weapon_id = &"prediction_agreement"
	context.initial_transform = Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, 25.0, 0.0)
	)
	context.initial_velocity = Vector3(65.0, -4.0, 0.0)
	context.torpedo_launch_mode = TorpedoLaunchMode.Type.AIR_DROPPED
	context.intended_launch_direction = Vector3.RIGHT
	_check(torpedo.configure(data, services), "torpedo configures")
	_check(torpedo.launch(context), "torpedo launches")
	var frame_count := 0
	while torpedo.launch_phase == TorpedoProjectile.LaunchPhase.AIRBORNE \
			and frame_count < 240:
		await physics_frame
		frame_count += 1
	_check(
		torpedo.launch_phase == TorpedoProjectile.LaunchPhase.ARMING,
		"the projectile reaches its real water-entry transition"
	)
	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity",
		9.8
	))
	var predicted_time := TorpedoSafeRunDistanceResolver \
		.airborne_fall_time_sec(25.0, 4.0, gravity)
	_predicted_distance_m = 65.0 * predicted_time
	_actual_distance_m = absf(torpedo.launch_position.x)
	_check(
		absf(_actual_distance_m - _predicted_distance_m) <= 8.0,
		"predicted airborne travel matches the real water-entry position"
	)
	torpedo.queue_free()
	await process_frame
	await process_frame
	print(
		(
			"AIR_DROPPED_TORPEDO_PREDICTION_AGREEMENT_TEST %s "
			+ "predicted=%.3f actual=%.3f error=%.3f"
		)
		% [
			"PASS" if _failures.is_empty() else "FAIL",
			_predicted_distance_m,
			_actual_distance_m,
			absf(_actual_distance_m - _predicted_distance_m),
		]
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("AIR TORPEDO PREDICTION: %s" % label)
