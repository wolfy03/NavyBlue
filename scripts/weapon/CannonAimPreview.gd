extends MeshInstance3D
class_name CannonAimPreview

@export_range(0.05, 0.5, 0.05) var update_interval_sec := 0.1
@export_range(32, 192, 1) var range_circle_segments := 96
@export var height_above_water_m := 1.0
@export var range_color := Color(1.0, 0.78, 0.2, 0.68)
@export var ready_color := Color(1.0, 0.92, 0.32, 0.9)
@export var unavailable_color := Color(1.0, 0.25, 0.16, 0.72)

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
	var cannons := owner_ship.combat.get_weapons_by_type(
		WeaponTypes.Type.CANNON
	)
	if cannons.is_empty():
		visible = false
		return
	var maximum_range := 0.0
	for cannon in cannons:
		maximum_range = maxf(maximum_range, cannon.get_range_m())
	if maximum_range <= 0.0:
		visible = false
		return

	_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _preview_material)
	_draw_range_circle(maximum_range)
	if owner_ship.combat.has_aim_point:
		_draw_aim_line(
			cannons[0],
			owner_ship.combat.aim_point
		)
	_preview_mesh.surface_end()
	visible = true


func _draw_range_circle(radius: float) -> void:
	var center := Vector3(0.0, height_above_water_m, 0.0)
	_preview_mesh.surface_set_color(range_color)
	for index in range_circle_segments:
		var first_angle := TAU * float(index) / float(range_circle_segments)
		var second_angle := TAU * float(index + 1) \
			/ float(range_circle_segments)
		_preview_mesh.surface_add_vertex(
			center + Vector3(cos(first_angle), 0.0, sin(first_angle)) * radius
		)
		_preview_mesh.surface_add_vertex(
			center + Vector3(cos(second_angle), 0.0, sin(second_angle)) * radius
		)


func _draw_aim_line(cannon: WeaponMount, world_point: Vector3) -> void:
	if cannon == null:
		return
	var origin := owner_ship.to_local(cannon.get_muzzle_position())
	origin.y = height_above_water_m
	var target := owner_ship.to_local(world_point)
	target.y = height_above_water_m
	var offset := target - origin
	if offset.length_squared() <= 0.01:
		return
	target = origin + offset.normalized() * minf(
		offset.length(),
		cannon.get_range_m()
	)
	_preview_mesh.surface_set_color(
		ready_color if cannon.can_fire_at(world_point) else unavailable_color
	)
	_preview_mesh.surface_add_vertex(origin)
	_preview_mesh.surface_add_vertex(target)


func _hide_preview() -> void:
	if not visible:
		return
	_preview_mesh.clear_surfaces()
	visible = false
