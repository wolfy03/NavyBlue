extends Node3D
class_name WaterSplashEffect

signal deactivated(effect)

@export var splash_audio: AudioStream
@export_range(0.2, 12.0, 0.1, "or_greater") var base_lifetime: float = 2.6
@export_range(1.0, 120.0, 1.0, "or_greater") var audio_max_distance: float = 180.0
@export_range(-48.0, 12.0, 0.1) var base_volume_db: float = -8.0
@export_range(0.5, 2.0, 0.01) var min_pitch: float = 0.85
@export_range(0.5, 2.0, 0.01) var max_pitch: float = 1.18

@onready var main_plume: GPUParticles3D = $MainPlumeParticles
@onready var droplets: GPUParticles3D = $DropletParticles
@onready var mist: GPUParticles3D = $MistParticles
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var lifetime_timer: Timer = $LifetimeTimer

var active: bool = false
var last_activated_msec: int = 0


func _ready() -> void:
	_setup_particles()
	lifetime_timer.one_shot = true
	if not lifetime_timer.timeout.is_connected(_on_lifetime_timeout):
		lifetime_timer.timeout.connect(_on_lifetime_timeout)
	deactivate()


func activate(world_position: Vector3, strength: float, impact_velocity: Vector3, surface_normal: Vector3) -> void:
	active = true
	visible = true
	set_process(false)
	last_activated_msec = Time.get_ticks_msec()
	global_position = world_position
	_align_to_surface(surface_normal)

	var safe_strength := clampf(strength, 0.25, 4.0)
	var velocity_factor := clampf(impact_velocity.length() / 45.0, 0.65, 2.2)
	scale = Vector3.ONE * (0.65 + safe_strength * 0.22)
	_configure_particle_runtime(main_plume, 1.75 + safe_strength * 1.18, velocity_factor)
	_configure_particle_runtime(droplets, 1.65 + safe_strength * 1.15, velocity_factor)
	_configure_particle_runtime(mist, 1.45 + safe_strength * 1.1, 0.7)

	_restart_particles(main_plume)
	_restart_particles(droplets)
	_restart_particles(mist)
	_play_audio(safe_strength)

	lifetime_timer.start(base_lifetime + safe_strength * 0.35)


func deactivate() -> void:
	active = false
	visible = false
	scale = Vector3.ONE
	set_process(false)
	_stop_particles(main_plume)
	_stop_particles(droplets)
	_stop_particles(mist)
	if audio_player != null:
		audio_player.stop()
	if lifetime_timer != null:
		lifetime_timer.stop()
	deactivated.emit(self)


func is_available() -> bool:
	return not active


func _setup_particles() -> void:
	_setup_plume()
	_setup_droplets()
	_setup_mist()
	audio_player.stream = splash_audio
	audio_player.max_distance = audio_max_distance
	audio_player.unit_size = 18.0


func _setup_plume() -> void:
	main_plume.one_shot = true
	main_plume.amount = 48
	main_plume.lifetime = 1.2
	main_plume.explosiveness = 0.82
	main_plume.fixed_fps = 30
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 14.0
	material.initial_velocity_min = 8.0
	material.initial_velocity_max = 16.0
	material.gravity = Vector3(0.0, -13.0, 0.0)
	material.scale_min = 0.18
	material.scale_max = 0.42
	material.color = Color(0.74, 0.93, 1.0, 0.82)
	main_plume.process_material = material
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.35
	main_plume.draw_pass_1 = mesh


func _setup_droplets() -> void:
	droplets.one_shot = true
	droplets.amount = 82
	droplets.lifetime = 1.5
	droplets.explosiveness = 0.92
	droplets.fixed_fps = 30
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 52.0
	material.initial_velocity_min = 5.5
	material.initial_velocity_max = 15.0
	material.gravity = Vector3(0.0, -19.0, 0.0)
	material.scale_min = 0.035
	material.scale_max = 0.095
	material.color = Color(0.66, 0.88, 1.0, 0.76)
	droplets.process_material = material
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	droplets.draw_pass_1 = mesh


func _setup_mist() -> void:
	mist.one_shot = true
	mist.amount = 36
	mist.lifetime = 2.1
	mist.explosiveness = 0.55
	mist.fixed_fps = 20
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 64.0
	material.initial_velocity_min = 1.1
	material.initial_velocity_max = 3.2
	material.gravity = Vector3(0.0, 0.8, 0.0)
	material.scale_min = 0.45
	material.scale_max = 1.2
	material.color = Color(0.78, 0.92, 1.0, 0.28)
	mist.process_material = material
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	mist.draw_pass_1 = mesh


func _configure_particle_runtime(particles: GPUParticles3D, amount_ratio: float, speed_scale: float) -> void:
	particles.amount_ratio = clampf(amount_ratio, 0.1, 1.0)
	particles.speed_scale = clampf(speed_scale, 0.2, 3.0)


func _restart_particles(particles: GPUParticles3D) -> void:
	particles.emitting = false
	particles.restart()
	particles.emitting = true


func _stop_particles(particles: GPUParticles3D) -> void:
	if particles == null:
		return
	particles.emitting = false


func _play_audio(strength: float) -> void:
	if audio_player == null:
		return
	audio_player.stop()
	audio_player.stream = splash_audio
	if splash_audio == null:
		return
	audio_player.volume_db = clampf(base_volume_db + linear_to_db(clampf(strength, 0.25, 4.0)) * 0.35, -36.0, 3.0)
	audio_player.pitch_scale = clampf(0.92 + strength * 0.06, min_pitch, max_pitch)
	audio_player.play()


func _align_to_surface(surface_normal: Vector3) -> void:
	var normal := surface_normal.normalized()
	if normal.length_squared() <= 0.001:
		normal = Vector3.UP
	if normal.dot(Vector3.UP) < 0.0:
		normal = -normal
	var tangent := normal.cross(Vector3.FORWARD)
	if tangent.length_squared() <= 0.001:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(normal).normalized()
	global_basis = Basis(tangent, normal, bitangent)


func _on_lifetime_timeout() -> void:
	deactivate()
