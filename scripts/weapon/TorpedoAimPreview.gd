extends MeshInstance3D
class_name TorpedoAimPreview

@export_range(0.05, 0.5, 0.05) var update_interval_sec := 0.1
@export var maximum_preview_radius_m := 1800.0
@export var arc_segment_count := 24
@export var ready_color := Color(0.2, 0.95, 0.72, 0.75)
@export var unavailable_color := Color(1.0, 0.24, 0.2, 0.55)

var owner_ship: ShipUnit
var _elapsed_sec := 0.0
var _preview_mesh := ImmediateMesh.new()
var _preview_material := StandardMaterial3D.new()


func _ready() -> void:
	owner_ship = get_parent() as ShipUnit
	mesh = _preview_mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.vertex_color_use_as_albedo = true
	_preview_material.no_depth_test = true
	visible = false


func _process(delta: float) -> void:
	if owner_ship == null or not owner_ship.player_controlled \
			or owner_ship.combat == null:
		_hide_preview()
		return
	_elapsed_sec += delta
	if _elapsed_sec < update_interval_sec:
		return
	_elapsed_sec = 0.0
	_refresh_preview()


func _refresh_preview() -> void:
	_preview_mesh.clear_surfaces()
	var mounts := owner_ship.combat.get_weapons_by_type(
		WeaponTypes.Type.TORPEDO
	)
	if mounts.is_empty():
		visible = false
		return
	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _preview_material)
	for mount in mounts:
		_draw_mount_arc(mount)
		if owner_ship.combat.has_aim_point:
			_draw_aim_path(mount, owner_ship.combat.aim_point)
	_preview_mesh.surface_end()
	visible = true


func _draw_mount_arc(mount: WeaponMount) -> void:
	if mount.slot_data == null:
		return
	var start_angle := mount.slot_data.traverse_min_degrees
	var end_angle := mount.slot_data.traverse_max_degrees
	var base_angle := mount.slot_data.local_rotation_degrees.y
	var radius := minf(mount.get_range_m(), maximum_preview_radius_m)
	if radius <= 0.0:
		return
	var origin := mount.position
	origin.y += 0.3
	_preview_mesh.surface_set_color(
		ready_color if mount.reload_left <= 0.0 else unavailable_color
	)
	for index in arc_segment_count:
		var first_ratio := float(index) / float(arc_segment_count)
		var second_ratio := float(index + 1) / float(arc_segment_count)
		var first_angle := base_angle + _interpolate_traverse_angle(
			start_angle,
			end_angle,
			first_ratio
		)
		var second_angle := base_angle + _interpolate_traverse_angle(
			start_angle,
			end_angle,
			second_ratio
		)
		var first := origin + _direction_for_yaw(
			first_angle
		) * radius
		var second := origin + _direction_for_yaw(
			second_angle
		) * radius
		_preview_mesh.surface_add_vertex(first)
		_preview_mesh.surface_add_vertex(second)


func _draw_aim_path(mount: WeaponMount, world_point: Vector3) -> void:
	var origin := mount.position
	origin.y += 0.35
	var local_target := owner_ship.to_local(world_point)
	local_target.y = origin.y
	var offset := local_target - origin
	if offset.length_squared() <= 0.01:
		return
	local_target = origin + offset.normalized() * minf(
		offset.length(),
		mount.get_range_m()
	)
	_preview_mesh.surface_set_color(
		ready_color if mount.can_fire_at(world_point) else unavailable_color
	)
	_preview_mesh.surface_add_vertex(origin)
	_preview_mesh.surface_add_vertex(local_target)


func _direction_for_yaw(yaw_degrees: float) -> Vector3:
	var yaw := deg_to_rad(yaw_degrees)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _interpolate_traverse_angle(
		minimum_degrees: float,
		maximum_degrees: float,
		ratio: float
) -> float:
	var raw_span := maximum_degrees - minimum_degrees
	if absf(raw_span) >= 359.9:
		return minimum_degrees + 360.0 * ratio
	var wrapped_span := fposmod(raw_span, 360.0)
	return minimum_degrees + wrapped_span * ratio


func _hide_preview() -> void:
	if not visible:
		return
	_preview_mesh.clear_surfaces()
	visible = false
