extends Node3D
class_name DiveBombTargetPreview

# Draws the circular accuracy preview for player dive-bomb targeting. The ring is
# a flat annulus on the sea plane whose radius equals the bombing dispersion, so
# a tighter (more accurate) squadron shows a smaller circle. Built procedurally
# so it needs no separate scene asset.

@export var valid_color := Color(1.0, 0.55, 0.1, 0.5)
@export var invalid_color := Color(1.0, 0.12, 0.08, 0.55)
@export var line_width_m := 6.0
@export var height_offset_m := 1.5
@export var segments := 48

var _session: DiveBombTargetingSession
var _ring: MeshInstance3D
var _valid_material: StandardMaterial3D
var _invalid_material: StandardMaterial3D
var _active_material: Material
var _last_outer_radius := -1.0


func _ready() -> void:
	_ring = MeshInstance3D.new()
	add_child(_ring)
	_valid_material = _make_material(valid_color)
	_invalid_material = _make_material(invalid_color)
	visible = false
	set_process(false)
	set_physics_process(false)


func setup(session: DiveBombTargetingSession) -> void:
	shutdown()
	_session = session
	if _session == null:
		return
	_connect_if_needed(_session.targeting_started, _on_targeting_started)
	_connect_if_needed(_session.preview_changed, apply_preview)
	_connect_if_needed(_session.targeting_completed, _on_targeting_completed)
	_connect_if_needed(_session.targeting_cancelled, _on_targeting_cancelled)
	if _session.is_active():
		_on_targeting_started()


func shutdown() -> void:
	if _session != null:
		_disconnect_if_connected(
			_session.targeting_started,
			_on_targeting_started
		)
		_disconnect_if_connected(_session.preview_changed, apply_preview)
		_disconnect_if_connected(
			_session.targeting_completed,
			_on_targeting_completed
		)
		_disconnect_if_connected(
			_session.targeting_cancelled,
			_on_targeting_cancelled
		)
	_session = null
	_active_material = null
	visible = false


func apply_preview(preview: DiveBombPreview) -> void:
	if preview == null:
		visible = false
		return
	var outer_radius := maxf(preview.dispersion_radius_m, 1.0)
	if not is_equal_approx(outer_radius, _last_outer_radius):
		_last_outer_radius = outer_radius
		var inner_radius := maxf(
			outer_radius - maxf(line_width_m, 0.1),
			outer_radius * 0.6
		)
		_rebuild_ring(inner_radius, outer_radius)
	global_position = preview.target_point + Vector3.UP * height_offset_m
	_set_material(_valid_material if preview.valid else _invalid_material)
	visible = true


func _rebuild_ring(inner_radius: float, outer_radius: float) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := TAU / float(maxi(segments, 3))
	for index in maxi(segments, 3):
		var angle_a := step * float(index)
		var angle_b := step * float(index + 1)
		var outer_a := Vector3(cos(angle_a) * outer_radius, 0.0, sin(angle_a) * outer_radius)
		var outer_b := Vector3(cos(angle_b) * outer_radius, 0.0, sin(angle_b) * outer_radius)
		var inner_a := Vector3(cos(angle_a) * inner_radius, 0.0, sin(angle_a) * inner_radius)
		var inner_b := Vector3(cos(angle_b) * inner_radius, 0.0, sin(angle_b) * inner_radius)
		surface.add_vertex(outer_a)
		surface.add_vertex(outer_b)
		surface.add_vertex(inner_b)
		surface.add_vertex(outer_a)
		surface.add_vertex(inner_b)
		surface.add_vertex(inner_a)
	_ring.mesh = surface.commit()
	_active_material = null


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material


func _set_material(material: Material) -> void:
	if material == _active_material:
		return
	_active_material = material
	if _ring != null:
		_ring.material_override = material


func _on_targeting_started() -> void:
	visible = true
	if _session != null:
		apply_preview(_session.get_current_preview())


func _on_targeting_completed(_commands: Array[DiveBombCommand]) -> void:
	visible = false


func _on_targeting_cancelled(_reason: StringName) -> void:
	visible = false


func _connect_if_needed(signal_value: Signal, callback: Callable) -> void:
	if not signal_value.is_connected(callback):
		signal_value.connect(callback)


func _disconnect_if_connected(signal_value: Signal, callback: Callable) -> void:
	if signal_value.is_connected(callback):
		signal_value.disconnect(callback)
