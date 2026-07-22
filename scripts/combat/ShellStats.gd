class_name ShellStats
extends Resource

enum ShellType {
	AP,
	HE,
}

@export var shell_type: ShellType = ShellType.AP
@export_range(0.0, 10000.0, 0.1, "or_greater") var penetration: float = 120.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var base_damage: float = 40.0
@export_range(0.0, 10.0, 0.01, "or_greater") var penetration_damage_multiplier: float = 1.5
@export_range(0.0, 10.0, 0.01, "or_greater") var non_penetration_damage_multiplier: float = 0.05
@export_range(0.0, 10.0, 0.01, "or_greater") var ricochet_damage_multiplier: float = 0.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var explosion_damage: float = 0.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var explosion_radius: float = 0.0
@export_range(0.0, 90.0, 0.1) var ricochet_angle: float = 70.0


func get_shell_type_name() -> StringName:
	match shell_type:
		ShellType.AP:
			return &"AP"
		ShellType.HE:
			return &"HE"
	return &"UNKNOWN"
