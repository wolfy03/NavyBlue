extends Node3D
class_name SquadronCommandPathPresenter

var settings: AircraftCommandPresentationSettings
@onready var path_line: MeshInstance3D = %PathLine
@onready var destination_marker: MeshInstance3D = %DestinationMarker


func setup(next_settings: AircraftCommandPresentationSettings) -> void:
	settings = next_settings
	var material := path_line.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = settings.path_color


func update_path(start: Vector3, destination: Vector3) -> void:
	if settings == null:
		visible = false
		return
	var raised_start := start + Vector3.UP \
		* settings.path_height_offset_m
	var raised_destination := destination + Vector3.UP \
		* settings.path_height_offset_m
	var offset := raised_destination - raised_start
	var length := offset.length()
	if length <= 1.0:
		visible = false
		return
	var direction := offset / length
	global_position = raised_start + direction * length * 0.5
	look_at(raised_destination, Vector3.UP)
	path_line.scale = Vector3(
		settings.path_line_thickness_m,
		settings.path_line_thickness_m,
		length
	)
	destination_marker.global_position = raised_destination
	visible = true


func hide_path() -> void:
	visible = false


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
