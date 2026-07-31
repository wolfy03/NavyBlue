extends Resource
class_name TurretPreviewSettings

@export var ready_color := Color(0.15, 1.0, 0.25, 0.78)
@export var blocked_color := Color(1.0, 0.12, 0.08, 0.78)
@export var line_thickness_m := 0.7
@export var height_offset_m := 0.0
@export var refresh_interval_sec := 0.05
@export var preview_mount_warning_threshold := 32


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if line_thickness_m <= 0.0:
		errors.append("line_thickness_m must be greater than zero.")
	if refresh_interval_sec <= 0.0:
		errors.append("refresh_interval_sec must be greater than zero.")
	if preview_mount_warning_threshold < 0:
		errors.append(
			"preview_mount_warning_threshold must not be negative."
		)
	return errors
