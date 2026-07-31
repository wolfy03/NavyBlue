extends Node3D
class_name TorpedoAttackArrowPresenter

@export var settings: TorpedoAttackPresentationSettings
@export var valid_material: StandardMaterial3D
@export var short_drag_material: StandardMaterial3D
@export var invalid_material: StandardMaterial3D

@onready var shaft_root: Node3D = %ShaftRoot
@onready var shaft: MeshInstance3D = %Shaft
@onready var head_left_root: Node3D = %HeadLeftRoot
@onready var head_left: MeshInstance3D = %HeadLeft
@onready var head_right_root: Node3D = %HeadRightRoot
@onready var head_right: MeshInstance3D = %HeadRight
@onready var entry_marker: MeshInstance3D = %EntryMarker
@onready var release_marker: MeshInstance3D = %ReleaseMarker

var _session: TorpedoAttackTargetingSession
var _active_material: Material


func _ready() -> void:
	visible = false
	set_process(false)
	set_physics_process(false)


func setup(session: TorpedoAttackTargetingSession) -> void:
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
		_disconnect_if_connected(_session.targeting_started, _on_targeting_started)
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


func apply_preview(preview: TorpedoAttackPreview) -> void:
	if preview == null or not preview.valid:
		if preview == null:
			visible = false
			return
	var height := 0.0
	var squadrons := _session.get_active_squadrons() \
		if _session != null else []
	if not squadrons.is_empty():
		var profile := squadrons[0].get_torpedo_attack_profile()
		height = profile.preview_height_offset_m if profile != null else 0.0
	var start := preview.entry_point + Vector3.UP * height
	var end := preview.actual_release_point + Vector3.UP * height
	if not BoxLinePlacement.place_between(
		shaft_root,
		shaft,
		start,
		end,
		settings.line_thickness_m
	):
		visible = false
		return
	var direction := end - start
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		visible = false
		return
	direction = direction.normalized()
	var lateral := direction.cross(Vector3.UP).normalized()
	var head_back := end - direction * settings.arrow_head_length_m
	var left_end := head_back + lateral * settings.arrow_head_width_m
	var right_end := head_back - lateral * settings.arrow_head_width_m
	BoxLinePlacement.place_between(
		head_left_root,
		head_left,
		left_end,
		end,
		settings.line_thickness_m
	)
	BoxLinePlacement.place_between(
		head_right_root,
		head_right,
		right_end,
		end,
		settings.line_thickness_m
	)
	entry_marker.global_position = start
	release_marker.global_position = end
	entry_marker.scale = Vector3.ONE * settings.marker_scale_m
	release_marker.scale = Vector3.ONE * settings.marker_scale_m
	var material := invalid_material
	if preview.valid:
		material = valid_material \
			if preview.distance_satisfied else short_drag_material
	_set_material(material)
	visible = true


func _set_material(material: Material) -> void:
	if material == _active_material:
		return
	_active_material = material
	for mesh in [shaft, head_left, head_right, entry_marker, release_marker]:
		mesh.material_override = material


func _on_targeting_started() -> void:
	visible = true
	if _session != null:
		apply_preview(_session.get_current_preview())


func _on_targeting_completed(_commands: Array[TorpedoAttackCommand]) -> void:
	visible = false


func _on_targeting_cancelled(_reason: StringName) -> void:
	visible = false


func _connect_if_needed(signal_value: Signal, callback: Callable) -> void:
	if not signal_value.is_connected(callback):
		signal_value.connect(callback)


func _disconnect_if_connected(signal_value: Signal, callback: Callable) -> void:
	if signal_value.is_connected(callback):
		signal_value.disconnect(callback)
