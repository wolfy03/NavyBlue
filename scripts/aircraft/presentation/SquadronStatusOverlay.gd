extends PanelContainer
class_name SquadronStatusOverlay

@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func set_snapshot(snapshot: SquadronPresentationSnapshot) -> void:
	if snapshot == null:
		visible = false
		return
	status_label.text = (
		"%s  %s\n"
		+ "%s  %d/%d\n"
		+ "HP %d%%  %.0f m/s\n"
		+ "%s  %d\n"
		+ "%s"
	) % [
		snapshot.display_name,
		snapshot.role_name,
		snapshot.state_name,
		snapshot.alive_count,
		snapshot.total_count,
		roundi(snapshot.average_health_ratio * 100.0),
		snapshot.average_speed_mps,
		snapshot.weapon_name,
		snapshot.ammunition_count,
		snapshot.mission_name,
	]
	visible = true


func set_screen_anchor(
		camera: Camera3D,
		world_position: Vector3,
		offset_pixels: Vector2
) -> void:
	if camera == null or camera.is_position_behind(world_position):
		visible = false
		return
	position = camera.unproject_position(world_position) \
		+ offset_pixels
