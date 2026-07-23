extends GPUParticles3D
class_name ShipWakeEmitter

@export_range(0.01, 0.5, 0.01) var minimum_speed_ratio := 0.08
@export_range(2.0, 30.0, 0.5, "or_greater") var minimum_lifetime_sec := 8.0
@export_range(2.0, 30.0, 0.5, "or_greater") var maximum_lifetime_sec := 14.0
@export var wake_color := Color(0.78, 0.94, 1.0, 0.58)
@export var surface_offset_m := 0.12

var owner_ship: ShipUnit
var _configured := false
var _hull_length_m := 1.0


func _ready() -> void:
	owner_ship = get_parent() as ShipUnit
	emitting = false
	local_coords = false
	one_shot = false
	fixed_fps = 20
	fract_delta = true


func _process(_delta: float) -> void:
	if not _ensure_configured() or owner_ship.movement == null:
		emitting = false
		return
	var signed_speed := owner_ship.movement.current_speed_mps
	var maximum_speed := owner_ship.ship_data.max_speed_mps \
		if signed_speed >= 0.0 else owner_ship.ship_data.max_reverse_speed_mps
	var speed_ratio := clampf(
		absf(signed_speed) / maxf(maximum_speed, 0.01),
		0.0,
		1.0
	)
	if speed_ratio < minimum_speed_ratio:
		emitting = false
		return
	position.z = _hull_length_m * (0.47 if signed_speed >= 0.0 else -0.47)
	amount_ratio = clampf(
		(speed_ratio - minimum_speed_ratio) / (1.0 - minimum_speed_ratio),
		0.08,
		1.0
	)
	speed_scale = lerpf(0.7, 1.35, speed_ratio)
	emitting = true


func _ensure_configured() -> bool:
	if _configured:
		return true
	if owner_ship == null or owner_ship.ship_data == null:
		return false
	_configure_for_ship(owner_ship.ship_data)
	_configured = true
	return true


func _configure_for_ship(data: ShipData) -> void:
	var hull_width := maxf(data.hull_size.x, 1.0)
	_hull_length_m = maxf(data.hull_size.z, 1.0)
	position = Vector3(0.0, surface_offset_m, _hull_length_m * 0.47)
	amount = clampi(roundi(_hull_length_m * 0.9), 96, 320)
	lifetime = lerpf(
		minimum_lifetime_sec,
		maximum_lifetime_sec,
		clampf((_hull_length_m - 100.0) / 220.0, 0.0, 1.0)
	)
	var visibility_extent := maxf(
		1000.0,
		data.max_speed_mps * lifetime * 2.2 + _hull_length_m
	)
	visibility_aabb = AABB(
		Vector3.ONE * -visibility_extent,
		Vector3.ONE * visibility_extent * 2.0
	)

	var particle_process_material := ParticleProcessMaterial.new()
	particle_process_material.emission_shape = \
		ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particle_process_material.emission_box_extents = Vector3(
		hull_width * 0.3,
		0.04,
		maxf(_hull_length_m * 0.025, 2.0)
	)
	particle_process_material.direction = Vector3(0.0, 0.0, 1.0)
	particle_process_material.spread = 18.0
	particle_process_material.initial_velocity_min = 0.4
	particle_process_material.initial_velocity_max = 1.6
	particle_process_material.gravity = Vector3.ZERO
	particle_process_material.scale_min = 0.55
	particle_process_material.scale_max = 1.45
	var fade_gradient := Gradient.new()
	fade_gradient.set_color(
		0,
		Color(wake_color.r, wake_color.g, wake_color.b, wake_color.a)
	)
	fade_gradient.set_color(
		1,
		Color(wake_color.r, wake_color.g, wake_color.b, 0.0)
	)
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade_gradient
	particle_process_material.color_ramp = fade_texture
	process_material = particle_process_material

	var wake_mesh := PlaneMesh.new()
	wake_mesh.size = Vector2(
		maxf(hull_width * 0.48, 4.0),
		maxf(_hull_length_m * 0.045, 4.0)
	)
	var wake_material := StandardMaterial3D.new()
	wake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wake_material.vertex_color_use_as_albedo = true
	wake_material.albedo_color = Color.WHITE
	wake_material.no_depth_test = true
	wake_mesh.material = wake_material
	draw_pass_1 = wake_mesh
