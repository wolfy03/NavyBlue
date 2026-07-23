extends RefCounted
class_name BattleInputActions

const KEY_ACTIONS := {
	&"camera_move_forward": [KEY_UP],
	&"camera_move_backward": [KEY_DOWN],
	&"camera_move_left": [KEY_LEFT],
	&"camera_move_right": [KEY_RIGHT],
	&"camera_rotate_left": [KEY_Q],
	&"camera_rotate_right": [KEY_E],
	&"camera_fast_move": [KEY_SHIFT],
	&"camera_focus_selection": [KEY_F],
	&"camera_reset": [KEY_HOME],
	&"selection_additive": [KEY_SHIFT],
	&"command_cancel": [KEY_ESCAPE],
	&"ship_throttle_forward": [KEY_W],
	&"ship_throttle_reverse": [KEY_S],
	&"ship_rudder_left": [KEY_A],
	&"ship_rudder_right": [KEY_D],
	&"ship_fire": [KEY_CTRL],
	&"turret_pitch_up": [KEY_U],
	&"turret_pitch_down": [KEY_O],
	&"debug_toggle": [KEY_F10],
}

const MOUSE_ACTIONS := {
	&"camera_zoom_in": MOUSE_BUTTON_WHEEL_UP,
	&"camera_zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
	&"camera_drag": MOUSE_BUTTON_MIDDLE,
}

static func ensure_defaults() -> void:
	for action: StringName in KEY_ACTIONS:
		_ensure_action(action)
		if InputMap.action_get_events(action).is_empty():
			for keycode: Key in KEY_ACTIONS[action]:
				var event := InputEventKey.new()
				event.physical_keycode = keycode
				InputMap.action_add_event(action, event)
	for action: StringName in MOUSE_ACTIONS:
		_ensure_action(action)
		if InputMap.action_get_events(action).is_empty():
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_ACTIONS[action]
			InputMap.action_add_event(action, event)

static func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
