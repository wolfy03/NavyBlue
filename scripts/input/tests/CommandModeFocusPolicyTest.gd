extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var panel_scene := load(
		"res://scenes/ui/carrier_air_group_panel.tscn"
	) as PackedScene
	var panel := panel_scene.instantiate() \
		as CarrierAirGroupPanel
	root.add_child(panel)
	var input_manager := PlayerInputManager.new()
	root.add_child(input_manager)
	var text_input := LineEdit.new()
	root.add_child(text_input)
	await process_frame
	_check(
		panel.strike_button.focus_mode == Control.FOCUS_CLICK,
		"carrier buttons are mouse-focus only"
	)
	_check(
		panel.squadron_selector.focus_mode \
			== Control.FOCUS_CLICK,
		"carrier selector is excluded from TAB traversal"
	)
	var selected_index := panel.squadron_selector.selected
	panel.strike_button.grab_focus()
	input_manager.call(&"_input", _toggle_event())
	_check(
		input_manager.get_command_mode() \
			== PlayerInputManager.CommandMode.AIRCRAFT,
		"TAB toggles command mode once"
	)
	_check(
		panel.strike_button != root.gui_get_focus_owner(),
		"TAB releases non-text button focus"
	)
	_check(
		panel.squadron_selector.selected == selected_index,
		"TAB does not change the carrier selector"
	)
	text_input.grab_focus()
	input_manager.call(&"_input", _toggle_event())
	_check(
		root.gui_get_focus_owner() == text_input,
		"text entry focus is preserved during mode toggle"
	)
	panel.queue_free()
	input_manager.queue_free()
	text_input.queue_free()
	await process_frame
	for failure in _failures:
		push_error("COMMAND MODE FOCUS POLICY TEST: %s" % failure)
	print(
		"COMMAND_MODE_FOCUS_POLICY_TEST %s"
		% ("PASS" if _failures.is_empty() else "FAIL")
	)
	quit(0 if _failures.is_empty() else 1)


func _toggle_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"toggle_command_mode"
	event.pressed = true
	return event


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
