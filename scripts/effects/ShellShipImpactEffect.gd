extends Node3D
class_name ShellShipImpactEffect

@export_range(0.2, 8.0, 0.1, "or_greater") var lifetime_seconds := 2.4

@onready var flash_particles: GPUParticles3D = $FlashParticles
@onready var spark_particles: GPUParticles3D = $SparkParticles
@onready var smoke_particles: GPUParticles3D = $SmokeParticles
@onready var debris_particles: GPUParticles3D = $DebrisParticles
@onready var impact_light: OmniLight3D = $OmniLight3D
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var lifetime_timer: Timer = $LifetimeTimer

var active := false
var last_activated_msec := 0


func _ready() -> void:
	_setup_particles()
	lifetime_timer.one_shot = true
	if not lifetime_timer.timeout.is_connected(deactivate):
		lifetime_timer.timeout.connect(deactivate)
	deactivate()


func activate(
		world_position: Vector3,
		surface_normal: Vector3,
		incoming_velocity: Vector3,
		hit_outcome: HitOutcome.Type,
		shell_type: ShellStats.ShellType,
		strength: float
) -> void:
	active = true
	last_activated_msec = Time.get_ticks_msec()
	global_position = world_position
	_align_to_surface(surface_normal, incoming_velocity)
	var safe_strength := clampf(strength, 0.5, 4.0)
	scale = Vector3.ONE * (1.0 + safe_strength * 0.38)
	_configure_outcome(hit_outcome, shell_type)
	_restart(flash_particles)
	_restart(spark_particles)
	_restart(smoke_particles)
	_restart(debris_particles)
	impact_light.light_energy = 5.0 + safe_strength * 3.0
	impact_light.omni_range = 18.0 + safe_strength * 8.0
	impact_light.visible = true
	visible = true
	set_process(false)
	lifetime_timer.start(lifetime_seconds + safe_strength * 0.18)


func deactivate() -> void:
	active = false
	visible = false
	scale = Vector3.ONE
	_stop(flash_particles)
	_stop(spark_particles)
	_stop(smoke_particles)
	_stop(debris_particles)
	if impact_light != null:
		impact_light.visible = false
	if audio_player != null:
		audio_player.stop()
	if lifetime_timer != null:
		lifetime_timer.stop()


func is_available() -> bool:
	return not active


func _setup_particles() -> void:
	var effect_aabb := AABB(
		Vector3(-45.0, -30.0, -45.0),
		Vector3(90.0, 90.0, 90.0)
	)
	for particles in [
		flash_particles,
		spark_particles,
		smoke_particles,
		debris_particles,
	]:
		particles.one_shot = true
		particles.visibility_aabb = effect_aabb
		particles.local_coords = false

	flash_particles.amount = 14
	flash_particles.lifetime = 0.32
	flash_particles.explosiveness = 1.0
	var flash_material := ParticleProcessMaterial.new()
	flash_material.direction = Vector3.UP
	flash_material.spread = 55.0
	flash_material.initial_velocity_min = 3.0
	flash_material.initial_velocity_max = 10.0
	flash_material.gravity = Vector3.ZERO
	flash_material.scale_min = 1.8
	flash_material.scale_max = 4.5
	flash_material.color = Color(1.0, 0.72, 0.25, 0.95)
	flash_particles.process_material = flash_material
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 1.5
	flash_mesh.height = 3.0
	flash_particles.draw_pass_1 = flash_mesh

	spark_particles.amount = 46
	spark_particles.lifetime = 0.9
	spark_particles.explosiveness = 1.0
	var spark_material := ParticleProcessMaterial.new()
	spark_material.direction = Vector3.UP
	spark_material.spread = 68.0
	spark_material.initial_velocity_min = 12.0
	spark_material.initial_velocity_max = 34.0
	spark_material.gravity = Vector3.DOWN * 15.0
	spark_material.scale_min = 0.18
	spark_material.scale_max = 0.48
	spark_material.color = Color(1.0, 0.52, 0.12, 1.0)
	spark_particles.process_material = spark_material
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.16, 0.16, 1.4)
	spark_particles.draw_pass_1 = spark_mesh

	smoke_particles.amount = 24
	smoke_particles.lifetime = 2.2
	smoke_particles.explosiveness = 0.72
	var smoke_material := ParticleProcessMaterial.new()
	smoke_material.direction = Vector3.UP
	smoke_material.spread = 50.0
	smoke_material.initial_velocity_min = 2.0
	smoke_material.initial_velocity_max = 8.0
	smoke_material.gravity = Vector3.UP * 1.2
	smoke_material.scale_min = 2.5
	smoke_material.scale_max = 6.5
	smoke_material.color = Color(0.2, 0.19, 0.18, 0.72)
	smoke_particles.process_material = smoke_material
	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2(4.0, 4.0)
	smoke_particles.draw_pass_1 = smoke_mesh

	debris_particles.amount = 24
	debris_particles.lifetime = 1.3
	debris_particles.explosiveness = 1.0
	var debris_material := ParticleProcessMaterial.new()
	debris_material.direction = Vector3.UP
	debris_material.spread = 72.0
	debris_material.initial_velocity_min = 8.0
	debris_material.initial_velocity_max = 24.0
	debris_material.gravity = Vector3.DOWN * 12.0
	debris_material.scale_min = 0.2
	debris_material.scale_max = 0.6
	debris_material.color = Color(0.42, 0.35, 0.28, 1.0)
	debris_particles.process_material = debris_material
	var debris_mesh := BoxMesh.new()
	debris_mesh.size = Vector3(0.4, 0.25, 1.0)
	debris_particles.draw_pass_1 = debris_mesh


func _configure_outcome(
		hit_outcome: HitOutcome.Type,
		shell_type: ShellStats.ShellType
) -> void:
	var flash_ratio := 0.75
	var spark_ratio := 0.8
	var smoke_ratio := 0.45
	var debris_ratio := 0.45
	match hit_outcome:
		HitOutcome.Type.PENETRATED:
			flash_ratio = 1.0
			spark_ratio = 0.65
			smoke_ratio = 0.75
			debris_ratio = 0.65
		HitOutcome.Type.NON_PENETRATED:
			flash_ratio = 0.65
			spark_ratio = 1.0
			smoke_ratio = 0.4
			debris_ratio = 0.35
		HitOutcome.Type.RICOCHET:
			flash_ratio = 0.75
			spark_ratio = 1.0
			smoke_ratio = 0.22
			debris_ratio = 0.8
	if shell_type == ShellStats.ShellType.HE:
		flash_ratio = 1.0
		smoke_ratio = 1.0
		debris_ratio = maxf(debris_ratio, 0.75)
	flash_particles.amount_ratio = flash_ratio
	spark_particles.amount_ratio = spark_ratio
	smoke_particles.amount_ratio = smoke_ratio
	debris_particles.amount_ratio = debris_ratio


func _align_to_surface(
		surface_normal: Vector3,
		incoming_velocity: Vector3
) -> void:
	var normal := surface_normal.normalized()
	if normal.length_squared() <= 0.0001:
		normal = -incoming_velocity.normalized()
	if normal.length_squared() <= 0.0001:
		normal = Vector3.UP
	var tangent := normal.cross(Vector3.FORWARD)
	if tangent.length_squared() <= 0.0001:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	global_basis = Basis(tangent, normal, tangent.cross(normal).normalized())


func _restart(particles: GPUParticles3D) -> void:
	particles.emitting = false
	particles.restart()
	particles.emitting = true


func _stop(particles: GPUParticles3D) -> void:
	if particles != null:
		particles.emitting = false
