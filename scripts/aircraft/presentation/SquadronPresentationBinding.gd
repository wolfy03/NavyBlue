extends RefCounted
class_name SquadronPresentationBinding

var squadron_ref: WeakRef
var destination_changed_callback: Callable
var destination_reached_callback: Callable
var selection_changed_callback: Callable
var return_requested_callback: Callable
var recovery_completed_callback: Callable
var squadron_lost_callback: Callable
var tree_exiting_callback: Callable


func get_squadron() -> AircraftSquadron:
	if squadron_ref == null:
		return null
	var squadron := squadron_ref.get_ref() as AircraftSquadron
	return squadron \
		if squadron != null and is_instance_valid(squadron) else null


func clear() -> void:
	squadron_ref = null
	destination_changed_callback = Callable()
	destination_reached_callback = Callable()
	selection_changed_callback = Callable()
	return_requested_callback = Callable()
	recovery_completed_callback = Callable()
	squadron_lost_callback = Callable()
	tree_exiting_callback = Callable()
