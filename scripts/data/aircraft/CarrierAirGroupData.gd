extends Resource
class_name CarrierAirGroupData

@export var id: String = ""
@export var squadron_templates: Array[SquadronData] = []
@export_range(1, 16, 1, "or_greater") var maximum_active_squadrons: int = 2
@export var launch_cooldown_sec: float = 6.0
@export var recovery_cooldown_sec: float = 8.0
@export var launch_local_position: Vector3 = Vector3(0.0, 18.0, -70.0)
@export var recovery_local_position: Vector3 = Vector3(0.0, 18.0, 70.0)
@export var ai_profile: CarrierAirGroupAIProfile
