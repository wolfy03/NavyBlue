extends RefCounted
class_name UIFocusPolicy


static func make_mouse_only(root: Control) -> void:
	if root == null:
		return
	var pending: Array[Control] = [root]
	while not pending.is_empty():
		var control: Control = pending.pop_back() as Control
		if control is Button \
				or control is OptionButton \
				or control is Slider:
			control.focus_mode = Control.FOCUS_CLICK
		for child in control.get_children():
			if child is Control:
				pending.append(child as Control)
