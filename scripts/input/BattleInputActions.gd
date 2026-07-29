extends RefCounted
class_name BattleInputActions

const KEY_ACTIONS := {
	&"camera_move_forward": [KEY_W, KEY_UP],
	&"camera_move_backward": [KEY_S, KEY_DOWN],
	&"camera_move_left": [KEY_A, KEY_LEFT],
	&"camera_move_right": [KEY_D, KEY_RIGHT],
	&"camera_rotate_left": [KEY_Q],
	&"camera_rotate_right": [KEY_E],
	&"camera_fast_move": [KEY_SHIFT],
	&"camera_focus_selection": [KEY_F],
	&"camera_reset": [KEY_HOME],
	&"selection_additive": [KEY_SHIFT],
	&"command_cancel": [KEY_ESCAPE],
	&"toggle_command_mode": [KEY_TAB],
	&"ship_throttle_forward": [KEY_I],
	&"ship_throttle_reverse": [KEY_K],
	&"ship_rudder_left": [KEY_J],
	&"ship_rudder_right": [KEY_L],
	&"ship_fire": [KEY_CTRL],
	&"ship_fire_cannon": [KEY_CTRL],
	&"ship_fire_torpedo": [KEY_T],
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
	if not InputMap.has_action(&"aircraft_special_action") \
			or InputMap.action_get_events(
				&"aircraft_special_action"
			).is_empty():
		push_warning(
			"aircraft_special_action has no bound input event."
		)
	if not InputMap.has_action(&"toggle_command_mode") \
			or InputMap.action_get_events(
				&"toggle_command_mode"
			).is_empty():
		push_warning(
			"toggle_command_mode has no bound input event."
		)

static func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
