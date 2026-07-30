extends PooledEffectBase
class_name TorpedoShipImpactEffect

@export_range(0.5, 8.0, 0.1, "or_greater") var lifetime_seconds := 3.0

@onready var flash_particles: GPUParticles3D = $UnderwaterFlashParticles
@onready var bubble_particles: GPUParticles3D = $BubbleParticles
@onready var debris_particles: GPUParticles3D = $DebrisParticles
@onready var smoke_particles: GPUParticles3D = $SmokeParticles
@onready var shockwave_mesh: MeshInstance3D = $ShockwaveMesh
@onready var impact_light: OmniLight3D = $OmniLight3D
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var lifetime_timer: Timer = $LifetimeTimer

var _age_seconds := 0.0
var _shockwave_material: StandardMaterial3D


func _ready() -> void:
	_setup_particles()
	_setup_shockwave()
	lifetime_timer.one_shot = true
	if not lifetime_timer.timeout.is_connected(deactivate):
		lifetime_timer.timeout.connect(deactivate)
	deactivate()


func _on_activate(request: EffectRequest) -> void:
	global_position = request.position
	var safe_strength := clampf(request.strength, 1.0, 4.0)
	scale = Vector3.ONE * (1.2 + safe_strength * 0.55)
	_age_seconds = 0.0
	_align_to_normal(request.normal)
	flash_particles.amount_ratio = 1.0
	bubble_particles.amount_ratio = clampf(0.45 + safe_strength * 0.18, 0.0, 1.0)
	debris_particles.amount_ratio = clampf(0.35 + safe_strength * 0.2, 0.0, 1.0)
	smoke_particles.amount_ratio = clampf(0.4 + safe_strength * 0.16, 0.0, 1.0)
	_restart(flash_particles)
	_restart(bubble_particles)
	_restart(debris_particles)
	_restart(smoke_particles)
	shockwave_mesh.scale = Vector3.ONE * 0.25
	shockwave_mesh.visible = true
	if _shockwave_material != null:
		_shockwave_material.albedo_color.a = 0.7
	impact_light.light_energy = 8.0 + safe_strength * 4.0
	impact_light.omni_range = 24.0 + safe_strength * 12.0
	impact_light.visible = true
	set_process(true)
	lifetime_timer.start(lifetime_seconds + safe_strength * 0.2)


func _process(delta: float) -> void:
	if not active:
		return
	_age_seconds += delta
	var normalized_age := clampf(_age_seconds / 1.2, 0.0, 1.0)
	shockwave_mesh.scale = Vector3.ONE * lerpf(0.25, 8.0, normalized_age)
	if _shockwave_material != null:
		var color := _shockwave_material.albedo_color
		color.a = lerpf(0.7, 0.0, normalized_age)
		_shockwave_material.albedo_color = color
	if normalized_age >= 1.0:
		shockwave_mesh.visible = false


func _on_deactivate() -> void:
	scale = Vector3.ONE
	set_process(false)
	_stop(flash_particles)
	_stop(bubble_particles)
	_stop(debris_particles)
	_stop(smoke_particles)
	if shockwave_mesh != null:
		shockwave_mesh.visible = false
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
		Vector3(-65.0, -45.0, -65.0),
		Vector3(130.0, 130.0, 130.0)
	)
	for particles in [
		flash_particles,
		bubble_particles,
		debris_particles,
		smoke_particles,
	]:
		particles.one_shot = true
		particles.visibility_aabb = effect_aabb
		particles.local_coords = false

	flash_particles.amount = 24
	flash_particles.lifetime = 0.45
	flash_particles.explosiveness = 1.0
	var flash_material := ParticleProcessMaterial.new()
	flash_material.direction = Vector3.UP
	flash_material.spread = 180.0
	flash_material.initial_velocity_min = 5.0
	flash_material.initial_velocity_max = 16.0
	flash_material.gravity = Vector3.ZERO
	flash_material.scale_min = 3.0
	flash_material.scale_max = 7.5
	flash_material.color = Color(0.72, 0.94, 1.0, 0.95)
	flash_particles.process_material = flash_material
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 2.4
	flash_mesh.height = 4.8
	flash_particles.draw_pass_1 = flash_mesh

	bubble_particles.amount = 70
	bubble_particles.lifetime = 2.6
	bubble_particles.explosiveness = 0.92
	var bubble_material := ParticleProcessMaterial.new()
	bubble_material.direction = Vector3.UP
	bubble_material.spread = 48.0
	bubble_material.initial_velocity_min = 7.0
	bubble_material.initial_velocity_max = 22.0
	bubble_material.gravity = Vector3.UP * 3.5
	bubble_material.scale_min = 0.8
	bubble_material.scale_max = 2.8
	bubble_material.color = Color(0.68, 0.88, 0.95, 0.66)
	bubble_particles.process_material = bubble_material
	var bubble_mesh := SphereMesh.new()
	bubble_mesh.radius = 0.75
	bubble_mesh.height = 1.5
	bubble_particles.draw_pass_1 = bubble_mesh

	debris_particles.amount = 42
	debris_particles.lifetime = 1.8
	debris_particles.explosiveness = 1.0
	var debris_material := ParticleProcessMaterial.new()
	debris_material.direction = Vector3.UP
	debris_material.spread = 85.0
	debris_material.initial_velocity_min = 10.0
	debris_material.initial_velocity_max = 30.0
	debris_material.gravity = Vector3.DOWN * 9.8
	debris_material.scale_min = 0.35
	debris_material.scale_max = 1.0
	debris_material.color = Color(0.22, 0.2, 0.18, 1.0)
	debris_particles.process_material = debris_material
	var debris_mesh := BoxMesh.new()
	debris_mesh.size = Vector3(0.65, 0.45, 1.6)
	debris_particles.draw_pass_1 = debris_mesh

	smoke_particles.amount = 34
	smoke_particles.lifetime = 3.0
	smoke_particles.explosiveness = 0.65
	var smoke_material := ParticleProcessMaterial.new()
	smoke_material.direction = Vector3.UP
	smoke_material.spread = 60.0
	smoke_material.initial_velocity_min = 3.0
	smoke_material.initial_velocity_max = 11.0
	smoke_material.gravity = Vector3.UP * 1.8
	smoke_material.scale_min = 3.5
	smoke_material.scale_max = 8.0
	smoke_material.color = Color(0.18, 0.2, 0.21, 0.68)
	smoke_particles.process_material = smoke_material
	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2(5.5, 5.5)
	smoke_particles.draw_pass_1 = smoke_mesh


func _setup_shockwave() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 2.6
	ring.outer_radius = 3.2
	_shockwave_material = StandardMaterial3D.new()
	_shockwave_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shockwave_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shockwave_material.albedo_color = Color(0.72, 0.95, 1.0, 0.7)
	_shockwave_material.emission_enabled = true
	_shockwave_material.emission = Color(0.45, 0.82, 1.0)
	_shockwave_material.emission_energy_multiplier = 2.0
	ring.material = _shockwave_material
	shockwave_mesh.mesh = ring


func _align_to_normal(surface_normal: Vector3) -> void:
	var normal := surface_normal.normalized()
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
