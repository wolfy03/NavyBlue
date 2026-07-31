extends Node3D
class_name SquadronCommandPathPresenter

var settings: AircraftCommandPresentationSettings
var _squadron_ref: WeakRef
var _runtime_material: StandardMaterial3D
@onready var path_line: MeshInstance3D = %PathLine
@onready var destination_marker: MeshInstance3D = %DestinationMarker


func setup(next_settings: AircraftCommandPresentationSettings) -> void:
	settings = next_settings
	_create_runtime_material()


func activate(squadron: AircraftSquadron) -> void:
	_squadron_ref = weakref(squadron) \
		if squadron != null and is_instance_valid(squadron) else null
	set_process(false)
	set_physics_process(false)


func deactivate() -> void:
	_squadron_ref = null
	hide_path()
	set_process(false)
	set_physics_process(false)


func update_path(
		start: Vector3,
		destination: Vector3,
		command_plane_height_m: float
) -> void:
	if settings == null:
		visible = false
		return
	var display_height := command_plane_height_m \
		+ settings.path_height_offset_m
	var raised_start := Vector3(start.x, display_height, start.z)
	var raised_destination := Vector3(
		destination.x,
		display_height,
		destination.z
	)
	if not BoxLinePlacement.place_between(
		self,
		path_line,
		raised_start,
		raised_destination,
		settings.path_line_thickness_m
	):
		hide_path()
		return
	destination_marker.global_position = raised_destination
	destination_marker.visible = true
	visible = true


func hide_path() -> void:
	visible = false
	path_line.visible = false
	destination_marker.visible = false


func should_show_path(
		squadron: AircraftSquadron,
		destination: SquadronDestinationSnapshot
) -> bool:
	if squadron == null or not is_instance_valid(squadron) \
			or destination == null \
			or destination.command_type != &"player_move" \
			or not destination.active \
			or destination.reached \
			or destination.loitering:
		return false
	return squadron.state not in [
		AircraftSquadron.State.RETURNING,
		AircraftSquadron.State.RECOVERING,
		AircraftSquadron.State.DESTROYED,
	]


func get_runtime_material() -> StandardMaterial3D:
	return _runtime_material


func _create_runtime_material() -> void:
	if settings == null or path_line == null:
		return
	if _runtime_material == null:
		var source_material := path_line.material_override \
			as StandardMaterial3D
		if source_material != null:
			_runtime_material = source_material.duplicate() \
				as StandardMaterial3D
	if _runtime_material == null:
		return
	_runtime_material.albedo_color = settings.path_color
	path_line.material_override = _runtime_material
	destination_marker.material_override = _runtime_material
