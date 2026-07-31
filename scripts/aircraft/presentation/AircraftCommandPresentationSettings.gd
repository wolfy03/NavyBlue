extends Resource
class_name AircraftCommandPresentationSettings

@export_category("Selection Box")
@export var selection_color := Color(0.15, 1.0, 0.25, 0.75)
@export var selection_line_thickness_m := 0.6
@export var bounds_padding_m := Vector3(25.0, 12.0, 25.0)
@export var minimum_box_size_m := Vector3(80.0, 30.0, 80.0)
@export var bounds_refresh_interval_sec := 0.08

@export_category("Command Path")
@export var path_color := Color(0.2, 1.0, 0.35, 0.55)
@export var path_line_thickness_m := 0.4
@export var path_height_offset_m := 2.0

@export_category("Status Overlay")
@export var status_offset_pixels := Vector2(8.0, 8.0)
@export var status_refresh_interval_sec := 0.2
