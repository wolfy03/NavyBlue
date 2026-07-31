extends Node3D
class_name TurretRangePreview

@onready var line_mesh: MeshInstance3D = %LineMesh

var _settings: TurretPreviewSettings
var _ready_material: Material
var _blocked_material: Material
var _bound_mount_ref: WeakRef
var _last_ready_state := false
var _has_ready_state := false


func _ready() -> void:
	visible = false
	set_process(false)
	set_physics_process(false)


func setup(
		settings: TurretPreviewSettings,
		ready_material: Material,
		blocked_material: Material
) -> void:
	_settings = settings
	_ready_material = ready_material
	_blocked_material = blocked_material


func activate(mount: WeaponMount) -> void:
	_bound_mount_ref = weakref(mount) \
		if mount != null and is_instance_valid(mount) else null
	_has_ready_state = false
	set_process(false)
	set_physics_process(false)


func apply_snapshot(snapshot: TurretPreviewSnapshot) -> void:
	if snapshot == null or not snapshot.visible or _settings == null:
		hide_preview()
		return
	var start := snapshot.origin \
		+ Vector3.UP * _settings.height_offset_m
	var end := start \
		+ snapshot.direction * snapshot.maximum_range_m
	if not BoxLinePlacement.place_between(
		self,
		line_mesh,
		start,
		end,
		_settings.line_thickness_m
	):
		hide_preview()
		return
	if not _has_ready_state \
			or _last_ready_state != snapshot.can_fire_now:
		_set_fire_ready(snapshot.can_fire_now)
	visible = true


func deactivate() -> void:
	_bound_mount_ref = null
	_has_ready_state = false
	hide_preview()


func hide_preview() -> void:
	visible = false
	if line_mesh != null:
		line_mesh.visible = false
	set_process(false)
	set_physics_process(false)


func get_bound_mount() -> WeaponMount:
	if _bound_mount_ref == null:
		return null
	var mount := _bound_mount_ref.get_ref() as WeaponMount
	return mount \
		if mount != null and is_instance_valid(mount) else null


func is_showing_ready_state() -> bool:
	return _has_ready_state and _last_ready_state


func has_ready_state() -> bool:
	return _has_ready_state


func get_last_ready_state() -> bool:
	return _last_ready_state


func _set_fire_ready(ready: bool) -> void:
	_last_ready_state = ready
	_has_ready_state = true
	line_mesh.material_override = _ready_material \
		if ready else _blocked_material
