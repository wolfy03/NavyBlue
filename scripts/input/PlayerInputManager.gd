extends Node

@export var water_height := 0.0
@export var pitch_step_degrees := 1.5

var controlled_ship
var camera

func setup(ship, view_camera: Camera3D, water_y: float = 0.0) -> void:
	controlled_ship = ship
	camera = view_camera
	water_height = water_y

func _physics_process(_delta: float) -> void:
	if controlled_ship == null:
		return
	var throttle_axis := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	var rudder_axis := float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D))
	var fire_pressed := Input.is_key_pressed(KEY_CTRL)
	controlled_ship.set_player_commands(throttle_axis, rudder_axis, fire_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if controlled_ship == null:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var aim_point = _mouse_to_water(event.position)
				if aim_point != null:
					controlled_ship.set_aim_point(aim_point)
			MOUSE_BUTTON_WHEEL_UP:
				if Input.is_key_pressed(KEY_CTRL):
					camera.adjust_zoom(1.0)
				else:
					controlled_ship.adjust_turret_pitch(pitch_step_degrees)
			MOUSE_BUTTON_WHEEL_DOWN:
				if Input.is_key_pressed(KEY_CTRL):
					camera.adjust_zoom(-1.0)
				else:
					controlled_ship.adjust_turret_pitch(-pitch_step_degrees)

func _mouse_to_water(screen_position: Vector2) -> Variant:
	if camera == null:
		return null
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001:
		return null
	var t: float = (water_height - origin.y) / direction.y
	if t < 0.0:
		return null
	return origin + direction * t
