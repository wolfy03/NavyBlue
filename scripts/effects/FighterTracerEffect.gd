extends PooledEffectBase
class_name FighterTracerEffect

@export var lifetime_seconds := 0.12
@export var tracer_width := 1.8

@onready var tracer_mesh: MeshInstance3D = get_node_or_null(
	"TracerMesh"
) as MeshInstance3D

var _age_seconds := 0.0


func _on_activate(request: EffectRequest) -> void:
	global_position = request.position
	_age_seconds = 0.0
	set_process(true)
	_build_tracer_mesh(
		request.end_position - request.position,
		clampi(
			ceili(
				float(request.rounds_fired)
				/ float(maxi(request.tracer_interval, 1))
			),
			1,
			3
		),
		request.hit_count > 0
	)


func _on_deactivate() -> void:
	_age_seconds = 0.0
	if tracer_mesh != null:
		tracer_mesh.mesh = null


func _process(delta: float) -> void:
	if not active:
		return
	_age_seconds += maxf(delta, 0.0)
	if _age_seconds >= maxf(lifetime_seconds, 0.01):
		deactivate()


func _build_tracer_mesh(
		local_end: Vector3,
		tracer_count: int,
		has_hit: bool
) -> void:
	if tracer_mesh == null:
		return
	var direction := local_end.normalized() \
		if local_end.length_squared() > 0.0001 else Vector3.FORWARD
	var side := direction.cross(Vector3.UP)
	if side.length_squared() <= 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 0.78, 0.2, 0.95) \
		if has_hit else Color(1.0, 0.92, 0.45, 0.9)
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 4.0
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(tracer_count):
		var centered_index := float(index) \
			- float(tracer_count - 1) * 0.5
		var offset := side * centered_index * tracer_width
		mesh.surface_add_vertex(offset)
		mesh.surface_add_vertex(local_end + offset)
	mesh.surface_end()
	tracer_mesh.mesh = mesh
