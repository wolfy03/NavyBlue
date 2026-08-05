extends RefCounted
class_name DiveBombTargetingTestSupport
## Shared helpers for the dive-bomb target resolver test family: spawns real
## ShipUnits and builds targeting requests without duplicating boilerplate in
## every test script.

const SHIP_SCENE_PATH := "res://scenes/unit/ship.tscn"


static func spawn_ship(
		parent: Node,
		team: StringName,
		position: Vector3
) -> ShipUnit:
	var ship := (load(SHIP_SCENE_PATH) as PackedScene).instantiate() as ShipUnit
	ship.team = team
	parent.add_child(ship)
	ship.global_position = position
	ship.set_physics_process(false)
	return ship


static func make_request(
		designation: Vector3,
		radius_m: float,
		team: StringName = &"player",
		explicit_target: ShipUnit = null,
		allow_fallback: bool = true
) -> DiveBombTargetRequest:
	var request := DiveBombTargetRequest.new()
	request.source = DiveBombTargetRequest.Source.PLAYER
	request.designated_world_position = designation
	request.acquisition_radius_m = radius_m
	request.requesting_team = team
	request.set_explicit_target(explicit_target)
	request.allow_position_fallback = allow_fallback
	return request


static func ships(list: Array) -> Array[ShipUnit]:
	var result: Array[ShipUnit] = []
	for value in list:
		var ship := value as ShipUnit
		if ship != null:
			result.append(ship)
	return result
