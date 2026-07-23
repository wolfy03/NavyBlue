extends Node3D
class_name ShipHitExplosionEffect

signal deactivated(effect)

@export_category("Distant Visibility")
@export_range(0.5, 10.0, 0.1, "or_greater") var minimum_visual_scale: float = 2.2
@export_range(0.5, 16.0, 0.1, "or_greater") var maximum_visual_scale: float = 5.0
@export_range(0.2, 10.0, 0.1, "or_greater") var effect_lifetime_sec: float = 4.0

@onready var flash_particles: GPUParticles3D = $FlashParticles
@onready var spark_particles: GPUParticles3D = $SparkParticles
@onready var smoke_particles: GPUParticles3D = $SmokeParticles
@onready var flash_light: OmniLight3D = $FlashLight
@onready var lifetime_timer: Timer = $LifetimeTimer

var active: bool = false
var last_activated_msec: int = 0
var _age_sec: float = 0.0
var _initial_light_energy: float = 8.0


func _ready() -> void:
	_setup_particles()
	lifetime_timer.one_shot = true
	if not lifetime_timer.timeout.is_connected(_on_lifetime_timeout):
		lifetime_timer.timeout.connect(_on_lifetime_timeout)
	deactivate()


func activate(world_position: Vector3, strength: float, penetrated: bool) -> void:
	active = true
	visible = true
	set_process(true)
	last_activated_msec = Time.get_ticks_msec()
	_age_sec = 0.0
	global_position = world_position
	var safe_strength := clampf(strength, 0.65, 4.0)
	var strength_ratio := clampf(inverse_lerp(0.65, 4.0, safe_strength), 0.0, 1.0)
	var visual_scale := lerpf(minimum_visual_scale, maximum_visual_scale, smoothstep(0.0, 1.0, strength_ratio))
	if penetrated:
		visual_scale *= 1.15
	scale = Vector3.ONE * visual_scale
	_initial_light_energy = (10.0 if penetrated else 7.0) * (0.8 + strength_ratio * 0.7)
	flash_light.light_energy = _initial_light_energy
	flash_light.visible = true
	_restart_particles(flash_particles)
	_restart_particles(spark_particles)
	_restart_particles(smoke_particles)
	lifetime_timer.start(effect_lifetime_sec + safe_strength * 0.25)


func deactivate() -> void:
	active = false
	visible = false
	set_process(false)
	scale = Vector3.ONE
	_stop_particles(flash_particles)
	_stop_particles(spark_particles)
	_stop_particles(smoke_particles)
	if flash_light != null:
		flash_light.visible = false
	if lifetime_timer != null:
		lifetime_timer.stop()
	deactivated.emit(self)


func is_available() -> bool:
	return not active


func _process(delta: float) -> void:
	_age_sec += delta
	var light_ratio := 1.0 - clampf(_age_sec / 0.32, 0.0, 1.0)
	flash_light.light_energy = _initial_light_energy * light_ratio
	flash_light.visible = light_ratio > 0.01


func _setup_particles() -> void:
	_setup_flash()
	_setup_sparks()
	_setup_smoke()
	flash_light.omni_range = 75.0
	flash_light.light_color = Color(1.0, 0.45, 0.08)
	flash_light.shadow_enabled = false


func _setup_flash() -> void:
	flash_particles.one_shot = true
	flash_particles.amount = 36
	flash_particles.lifetime = 0.55
	flash_particles.explosiveness = 0.92
	flash_particles.fixed_fps = 30
	flash_particles.visibility_aabb = AABB(Vector3.ONE * -32.0, Vector3.ONE * 64.0)
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 2.0
	process_material.initial_velocity_max = 9.0
	process_material.gravity = Vector3.ZERO
	process_material.scale_min = 0.8
	process_material.scale_max = 2.2
	process_material.color = Color(1.0, 0.44, 0.06, 0.96)
	flash_particles.process_material = process_material
	var mesh := SphereMesh.new()
	mesh.radius = 0.7
	mesh.height = 1.4
	mesh.material = _create_particle_material(Color(1.0, 0.18, 0.02, 0.98), 5.0, false)
	flash_particles.draw_pass_1 = mesh


func _setup_sparks() -> void:
	spark_particles.one_shot = true
	spark_particles.amount = 72
	spark_particles.lifetime = 1.45
	spark_particles.explosiveness = 0.96
	spark_particles.fixed_fps = 30
	spark_particles.visibility_aabb = AABB(Vector3(-48.0, -40.0, -48.0), Vector3(96.0, 112.0, 96.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 78.0
	process_material.initial_velocity_min = 8.0
	process_material.initial_velocity_max = 24.0
	process_material.gravity = Vector3(0.0, -18.0, 0.0)
	process_material.scale_min = 0.18
	process_material.scale_max = 0.48
	process_material.color = Color(1.0, 0.65, 0.16, 0.92)
	spark_particles.process_material = process_material
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.55
	mesh.material = _create_particle_material(Color(1.0, 0.42, 0.04, 0.95), 4.0, false)
	spark_particles.draw_pass_1 = mesh


func _setup_smoke() -> void:
	smoke_particles.one_shot = true
	smoke_particles.amount = 42
	smoke_particles.lifetime = 3.6
	smoke_particles.explosiveness = 0.62
	smoke_particles.fixed_fps = 20
	smoke_particles.visibility_aabb = AABB(Vector3(-40.0, -12.0, -40.0), Vector3(80.0, 100.0, 80.0))
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 42.0
	process_material.initial_velocity_min = 2.0
	process_material.initial_velocity_max = 6.0
	process_material.gravity = Vector3(0.0, 1.6, 0.0)
	process_material.scale_min = 1.2
	process_material.scale_max = 3.8
	process_material.color = Color(0.22, 0.19, 0.18, 0.58)
	smoke_particles.process_material = process_material
	var mesh := QuadMesh.new()
	mesh.size = Vector2(3.0, 3.0)
	mesh.material = _create_particle_material(Color(0.2, 0.17, 0.16, 0.62), 0.04, true)
	smoke_particles.draw_pass_1 = mesh


func _create_particle_material(color: Color, emission_energy: float, billboard: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.emission_enabled = emission_energy > 0.0
	material.emission = color
	material.emission_energy_multiplier = emission_energy
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return material


func _restart_particles(particles: GPUParticles3D) -> void:
	particles.emitting = false
	particles.restart()
	particles.emitting = true


func _stop_particles(particles: GPUParticles3D) -> void:
	if particles == null:
		return
	particles.restart()
	particles.emitting = false


func _on_lifetime_timeout() -> void:
	deactivate()
