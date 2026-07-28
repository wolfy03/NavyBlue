extends Resource
class_name SquadronData

@export var id: String = ""
@export var display_name: String = ""
@export var aircraft_data: AircraftData
@export_range(1, 64, 1, "or_greater") var aircraft_count: int = 4
@export var formation_spacing_m: float = 24.0
@export var launch_interval_sec: float = 0.25
@export var rearm_duration_sec: float = 15.0
@export var default_mission_data: AirMissionData
