extends RefCounted
class_name FighterTestSupport

const AIRCRAFT_SCENE := preload(
	"res://scenes/aircraft/aircraft_unit.tscn"
)
const FIGHTER_DATA: AircraftData = preload(
	"res://resources/aircraft/types/basic_fighter.tres"
)
const BOMBER_DATA: AircraftData = preload(
	"res://resources/aircraft/types/basic_dive_bomber.tres"
)


static func spawn_aircraft(
		parent: Node,
		data: AircraftData,
		team: StringName,
		position: Vector3,
		forward: Vector3 = Vector3.FORWARD
) -> AircraftUnit:
	var aircraft := AIRCRAFT_SCENE.instantiate() as AircraftUnit
	parent.add_child(aircraft)
	aircraft.global_position = position
	var safe_forward := forward.normalized() \
		if forward.length_squared() > 0.0001 else Vector3.FORWARD
	aircraft.global_transform.basis = Basis.looking_at(
		safe_forward,
		Vector3.UP
	)
	aircraft.setup(data, team, Vector3.ZERO)
	aircraft.set_physics_process(false)
	return aircraft


static func find_carrier(
		battle: BattleScene,
		team: StringName
) -> ShipUnit:
	for value in battle.get_battle_units():
		var ship := value as ShipUnit
		if ship != null \
				and ship.team == team \
				and ship.ship_id == "cv_seabastion":
			return ship
	return null


static func stop_carrier_ai(carrier: ShipUnit) -> void:
	if carrier != null and carrier.carrier_air_group_ai != null:
		carrier.carrier_air_group_ai.shutdown()
		carrier.carrier_air_group_ai.process_mode = \
			Node.PROCESS_MODE_DISABLED
