extends RefCounted
class_name AirDroppedTorpedoLaunchRequest

var source_aircraft: AircraftUnit
var source_squadron: AircraftSquadron
var launch_position := Vector3.ZERO
var launch_direction := Vector3.FORWARD
var aircraft_velocity := Vector3.ZERO
var target_point := Vector3.ZERO
var target_ship: ShipUnit
var torpedo_data: TorpedoProjectileData
var command_id := 0
