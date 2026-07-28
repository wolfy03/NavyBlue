extends Resource
class_name AirMissionData

enum MissionType {
	MOVE,
	STRIKE_SHIP,
	RETURN_TO_CARRIER,
	INTERCEPT_AIRCRAFT,
	TORPEDO_ATTACK,
	RECON,
}

@export var id: String = ""
@export var mission_type: MissionType = MissionType.STRIKE_SHIP
@export var attack_altitude_m: float = 150.0
@export var attack_pass_count: int = 1
@export var target_prediction_enabled: bool = true
@export var return_after_attack: bool = true
