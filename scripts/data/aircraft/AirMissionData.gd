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

@export_category("AI Approach Repath")
@export var approach_repath_interval_sec: float = 0.5
@export var approach_repath_threshold_m: float = 150.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if attack_altitude_m < 0.0:
		errors.append("attack_altitude_m must not be negative.")
	if attack_pass_count <= 0:
		errors.append("attack_pass_count must be greater than zero.")
	if approach_repath_interval_sec < 0.0:
		errors.append(
			"approach_repath_interval_sec must not be negative."
		)
	if approach_repath_threshold_m < 0.0:
		errors.append(
			"approach_repath_threshold_m must not be negative."
		)
	return errors
