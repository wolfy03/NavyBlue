extends RefCounted
class_name FleetOrderDispatcher


func dispatch_context(
		ship: ShipUnit,
		context: FleetMemberContext,
		request_immediate_targeting := false
) -> void:
	if ship == null or context == null or not is_instance_valid(ship):
		return
	ship.on_fleet_tactical_context_changed(context)
	if request_immediate_targeting and ship.targeting != null:
		ship.targeting.request_immediate_evaluation()
