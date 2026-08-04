extends "res://scripts/weapon/mount/WeaponMount.gd"
class_name CannonMount

static var _warned_unreachable_range_ids: Dictionary = {}

@export var projectile_scene: PackedScene = preload("res://scenes/weapon/projectile.tscn")
@export var shell_stats: ShellStats = preload("res://scripts/combat/default_ap_shell.tres")
@export var yaw_speed := 7.5
@export var min_pitch_degrees := 1.0
@export var max_pitch_degrees := 55.0
@export var pitch_degrees := 18.0
@export var automatic_ballistic_pitch := true
@export var pitch_speed_deg_sec := 12.0
@export var pitch_alignment_tolerance_degrees := 0.5
@export_range(-10.0, 10.0, 0.5) var manual_pitch_offset_deg := 0.0
@export var muzzle_velocity := 36.0
@export var reload_seconds := 1.2
@export var bonus_projectile_spread_degrees := 0.6
@export_range(1.0, 1.05, 0.001) var physical_range_tolerance_ratio := 1.005

## Optional per-shell launch deviation source (AI gunnery dispersion).
## Duck-typed to avoid a class reference cycle with the fire control:
## must expose get_shell_deviation_radians(mount, shell_index, count) -> Vector2.
var shell_deviation_provider: RefCounted

## Cached integer digest of everything that decides which fire-control weapon
## group this mount belongs to (weapon, projectile, muzzle speed, gravity,
## range, accuracy profile). Recomputed only when the ballistic configuration
## actually changes, so fire control never formats a long key string per frame.
var _cached_ballistic_group_hash := 0
var _cached_ballistic_revision := -1
var _ballistic_configuration_revision := 0


## Bumped whenever a value feeding the group hash changes. Runtime upgrades go
## through set_runtime_stats/setup, both of which invalidate the cache.
func invalidate_ballistic_configuration() -> void:
	_ballistic_configuration_revision += 1


func get_ballistic_configuration_revision() -> int:
	return _ballistic_configuration_revision


## Structured int hash instead of a formatted string. Resource instance ids
## alone cannot distinguish runtime upgrades, so the quantized ballistic values
## and the accuracy profile identity are folded in as well.
func get_ballistic_group_hash() -> int:
	if _cached_ballistic_revision == _ballistic_configuration_revision:
		return _cached_ballistic_group_hash
	_cached_ballistic_revision = _ballistic_configuration_revision
	if weapon_data == null or weapon_data.id.is_empty():
		_cached_ballistic_group_hash = hash([&"mount", get_instance_id()])
		return _cached_ballistic_group_hash
	var projectile_data := weapon_data.projectile_data
	var accuracy_profile := weapon_data.gunnery_accuracy_profile
	_cached_ballistic_group_hash = hash([
		weapon_data.id,
		weapon_data.get_instance_id(),
		projectile_data.get_instance_id() if projectile_data != null else 0,
		# Quantized so float noise cannot split an otherwise identical group.
		roundi(get_modified_projectile_speed(muzzle_velocity) * 1000.0),
		roundi(get_effective_gravity_mps2() * 1000.0),
		roundi(get_range_m() * 1000.0),
		accuracy_profile.get_instance_id() if accuracy_profile != null else 0,
	])
	return _cached_ballistic_group_hash

@onready var base_mesh: MeshInstance3D = $Base
@onready var barrel_pivot: Node3D = $BarrelPivot
@onready var barrel_mesh: MeshInstance3D = $BarrelPivot/Barrel
@onready var muzzle: Node3D = $BarrelPivot/Muzzle


func setup(
		data: WeaponData,
		slot: ShipWeaponSlotData,
		ship: ShipUnit,
		team: StringName,
		next_battle_services: BattleServices = null
) -> void:
	super.setup(data, slot, ship, team, next_battle_services)
	invalidate_ballistic_configuration()
	if weapon_data != null:
		reload_seconds = weapon_data.reload_seconds
		muzzle_velocity = weapon_data.muzzle_velocity
		yaw_speed = weapon_data.turret_turn_speed_degrees
		max_pitch_degrees = weapon_data.max_pitch_degrees
		if weapon_data.projectile_scene != null:
			projectile_scene = weapon_data.projectile_scene
	if slot_data != null:
		min_pitch_degrees = slot_data.elevation_min_degrees
		max_pitch_degrees = minf(max_pitch_degrees, slot_data.elevation_max_degrees)
	var team_color := ship.team_color if ship != null else Color.WHITE
	_apply_team_materials(team_color)
	if weapon_data != null \
			and not is_configured_range_physically_reachable() \
			and not weapon_data.id.is_empty() \
			and not _warned_unreachable_range_ids.has(weapon_data.id):
		_warned_unreachable_range_ids[weapon_data.id] = true
		push_warning(
			"Configured cannon range exceeds the physical ballistic limit: %s"
			% weapon_data.id
		)


func _ready() -> void:
	barrel_pivot.rotation.x = deg_to_rad(pitch_degrees)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if has_aim_point:
		_turn_toward(aim_point, delta)
	barrel_pivot.rotation.x = deg_to_rad(pitch_degrees)


func get_fire_readiness_at(
		world_point: Vector3
) -> WeaponFireReadiness.State:
	var readiness := super.get_fire_readiness_at(world_point)
	if readiness != WeaponFireReadiness.State.READY:
		return readiness
	if muzzle == null:
		return WeaponFireReadiness.State.NO_MUZZLE
	if not _is_aim_aligned(world_point, 3.0):
		return WeaponFireReadiness.State.NOT_ALIGNED
	var required_pitch: Variant = _calculate_ballistic_pitch_deg(world_point)
	if required_pitch == null:
		return WeaponFireReadiness.State.NO_BALLISTIC_SOLUTION
	var desired_pitch := float(required_pitch) + manual_pitch_offset_deg
	if desired_pitch < min_pitch_degrees or desired_pitch > max_pitch_degrees:
		return WeaponFireReadiness.State.NO_BALLISTIC_SOLUTION
	if absf(pitch_degrees - desired_pitch) \
			> pitch_alignment_tolerance_degrees:
		return WeaponFireReadiness.State.NOT_ELEVATION_ALIGNED
	return WeaponFireReadiness.State.READY


## Geometry-only engagement contract for automatic batteries. Reload,
## ammunition, and current alignment are deliberately excluded so target
## selection remains stable while a usable turret is cycling or traversing.
func can_engage_world_point(world_point: Vector3) -> bool:
	if weapon_data == null \
			or not runtime_state.enabled \
			or not world_point.is_finite() \
			or not _has_projectile_available() \
			or not has_valid_preview_muzzle():
		return false
	var distance := get_distance_to_world_point(world_point)
	if distance < get_minimum_range_m() or distance > get_range_m():
		return false
	if not is_world_point_within_traverse(world_point):
		return false
	var required_pitch: Variant = _calculate_ballistic_pitch_deg(world_point)
	if required_pitch == null:
		return false
	var desired_pitch := float(required_pitch) + manual_pitch_offset_deg
	return desired_pitch >= min_pitch_degrees \
		and desired_pitch <= max_pitch_degrees


func get_rest_traverse_speed_degrees() -> float:
	return get_modified_traverse_speed(yaw_speed)


func adjust_pitch(delta_degrees: float) -> void:
	manual_pitch_offset_deg = clampf(
		manual_pitch_offset_deg + delta_degrees,
		-10.0,
		10.0
	)


func fire() -> bool:
	if muzzle == null or not can_fire_at(aim_point):
		return false
	var launched := 0
	var launch_count := get_salvo_projectile_count()
	for index in range(launch_count):
		if _launch_shell(index, launch_count):
			launched += 1
	if launched <= 0:
		return false
	reload_left = get_reload_seconds()
	return true


func _launch_shell(index: int, total_count: int) -> bool:
	var center_offset := float(total_count - 1) * 0.5
	var spread_offset_degrees := (
		float(index) - center_offset
	) * bonus_projectile_spread_degrees
	var launch_transform := muzzle.global_transform
	launch_transform.basis = launch_transform.basis.rotated(
		Vector3.UP,
		deg_to_rad(spread_offset_degrees)
	)
	if shell_deviation_provider != null \
			and shell_deviation_provider.has_method(
				&"get_shell_deviation_radians"
			):
		# AI gunnery dispersion: perturb the launch direction so every shell
		# still flies with real ballistics; misses fall in the water and keep
		# the existing splash/impact pipeline.
		var deviation: Vector2 = shell_deviation_provider.call(
			&"get_shell_deviation_radians",
			self,
			index,
			total_count
		)
		if deviation != Vector2.ZERO:
			launch_transform.basis = launch_transform.basis.rotated(
				Vector3.UP,
				deviation.x
			)
			launch_transform.basis = launch_transform.basis.rotated(
				launch_transform.basis.x.normalized(),
				deviation.y
			)
	var active_data := weapon_data.projectile_data if weapon_data != null else null
	if _is_projectile_spawn_disabled_for_diagnostics(active_data):
		# Diagnostic isolation: aiming, readiness and the fire request all ran;
		# only the projectile instantiation is skipped. Report success so the
		# reload cycle and per-mount fire sequence behave normally.
		return true
	var context := ProjectileLaunchContext.new()
	context.source_actor = owner_ship
	context.source_team = owner_team
	context.source_weapon_id = StringName(weapon_data.id) if weapon_data != null else StringName()
	context.source_projectile_data = active_data
	context.initial_transform = launch_transform
	context.initial_velocity = -launch_transform.basis.z.normalized() \
		* get_modified_projectile_speed(muzzle_velocity)
	context.aim_point = aim_point
	context.runtime_stats = runtime_stats.duplicate_stats()
	context.from_secondary_battery = is_secondary_battery_mount()
	if projectile_factory == null:
		push_error("CannonMount requires an injected ProjectileFactory.")
		return false
	var creation := projectile_factory.create_result(
		_get_projectile_scene(),
		_get_projectile_parent(),
		active_data,
		context
	)
	var projectile := creation.projectile
	if projectile == null:
		push_warning("Cannon mount could not create its shell projectile.")
		return false
	fired.emit(projectile)
	return true


func _is_projectile_spawn_disabled_for_diagnostics(
		_active_data: ProjectileData
) -> bool:
	if battle_services == null or battle_services.debug_settings == null:
		return false
	if not battle_services.debug_settings.disable_secondary_projectile_spawn:
		return false
	# Keyed on battery role, not projectile id: the same naval_gun_100mm serves
	# as a main battery on some hulls, and this diagnostic must isolate only
	# the automatic secondary battery.
	return is_secondary_battery_mount()


func is_secondary_battery_mount() -> bool:
	return slot_data != null \
		and slot_data.battery_role == BatteryRole.Type.SECONDARY


func get_muzzle_velocity_vector() -> Vector3:
	return get_projectile_launch_direction_world() \
		* get_modified_projectile_speed(muzzle_velocity)


func get_muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle != null else global_position


func has_valid_preview_muzzle() -> bool:
	return muzzle != null \
		and is_instance_valid(muzzle) \
		and muzzle.is_inside_tree() \
		and muzzle.global_position.is_finite()


func get_preview_muzzle_position() -> Vector3:
	return muzzle.global_position \
		if has_valid_preview_muzzle() else Vector3.ZERO


func get_projectile_launch_direction_world() -> Vector3:
	if not has_valid_preview_muzzle():
		return Vector3.ZERO
	var direction := -muzzle.global_transform.basis.z
	return direction.normalized() \
		if direction.is_finite() \
		and direction.length_squared() > 0.0001 \
		else Vector3.ZERO


func _get_projectile_scene() -> PackedScene:
	if weapon_data != null and weapon_data.projectile_scene != null:
		return weapon_data.projectile_scene
	return projectile_scene


func _turn_toward(world_point: Vector3, delta: float) -> void:
	update_traverse_toward(
		world_point,
		get_modified_traverse_speed(yaw_speed),
		delta
	)
	if automatic_ballistic_pitch:
		var ballistic_pitch: Variant = _calculate_ballistic_pitch_deg(world_point)
		if ballistic_pitch != null:
			var desired_pitch := float(ballistic_pitch) + manual_pitch_offset_deg
			if desired_pitch < min_pitch_degrees \
					or desired_pitch > max_pitch_degrees:
				return
			pitch_degrees = move_toward(
				pitch_degrees,
				desired_pitch,
				pitch_speed_deg_sec * delta
			)


func _has_projectile_available() -> bool:
	return _get_projectile_scene() != null


func _calculate_ballistic_pitch_deg(world_point: Vector3) -> Variant:
	if muzzle == null:
		return null
	var muzzle_position := muzzle.global_position
	var horizontal_offset := Vector2(
		world_point.x - muzzle_position.x,
		world_point.z - muzzle_position.z
	)
	var horizontal_distance := horizontal_offset.length()
	if horizontal_distance < 0.01:
		return null
	var effective_muzzle_velocity := get_modified_projectile_speed(
		muzzle_velocity
	)
	var vertical_offset := world_point.y - muzzle_position.y
	var angle: Variant = BallisticMath.solve_low_arc_angle(
		horizontal_distance,
		vertical_offset,
		effective_muzzle_velocity,
		get_effective_gravity_mps2()
	)
	return rad_to_deg(float(angle)) if angle != null else null


func get_effective_gravity_mps2() -> float:
	var shell_data := weapon_data.projectile_data as ShellProjectileData \
		if weapon_data != null else null
	return BallisticMath.get_effective_gravity_mps2(shell_data)


func get_physical_maximum_range_m() -> float:
	return BallisticMath.calculate_maximum_range(
		get_modified_projectile_speed(muzzle_velocity),
		get_effective_gravity_mps2(),
		max_pitch_degrees
	)


func is_configured_range_physically_reachable() -> bool:
	var physical_maximum := get_physical_maximum_range_m()
	return physical_maximum > 0.0 \
		and get_range_m() \
			<= physical_maximum * physical_range_tolerance_ratio


func _apply_team_materials(team_color: Color) -> void:
	if base_mesh == null or barrel_mesh == null:
		return
	var base_material := StandardMaterial3D.new()
	base_material.albedo_color = team_color.lightened(0.12)
	base_material.roughness = 0.72
	base_mesh.material_override = base_material
	var barrel_material := StandardMaterial3D.new()
	barrel_material.albedo_color = Color(0.12, 0.14, 0.16)
	barrel_material.roughness = 0.85
	barrel_mesh.material_override = barrel_material
