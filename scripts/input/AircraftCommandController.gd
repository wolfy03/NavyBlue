extends RefCounted
class_name AircraftCommandController

var selection_controller: AircraftSelectionController
var carrier_controller: CarrierCommandController


func setup(
		next_selection_controller: AircraftSelectionController,
		next_carrier_controller: CarrierCommandController
) -> void:
	shutdown()
	selection_controller = next_selection_controller
	carrier_controller = next_carrier_controller


func shutdown() -> void:
	if selection_controller != null:
		selection_controller.set_input_enabled(false)
		selection_controller.clear_selection()
	if carrier_controller != null and carrier_controller.is_targeting():
		carrier_controller.cancel_targeting()
	selection_controller = null
	carrier_controller = null


func set_input_enabled(enabled: bool) -> void:
	if selection_controller != null:
		selection_controller.set_input_enabled(enabled)


func has_selection() -> bool:
	return selection_controller != null \
		and selection_controller.has_selection()


func clear_selection() -> void:
	if selection_controller != null:
		selection_controller.clear_selection()


func execute_special_action() -> bool:
	return selection_controller != null \
		and selection_controller.execute_special_action()


func cancel_targeting() -> bool:
	if carrier_controller == null or not carrier_controller.is_targeting():
		return false
	carrier_controller.cancel_targeting()
	return true
