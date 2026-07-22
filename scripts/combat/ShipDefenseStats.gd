class_name ShipDefenseStats
extends Resource

@export_range(1.0, 100000.0, 1.0, "or_greater") var max_hp: float = 100.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var current_hp: float = 100.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var belt_armor: float = 60.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var deck_armor: float = 35.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var bow_armor: float = 30.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var stern_armor: float = 25.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var superstructure_armor: float = 15.0
@export_range(0.0, 0.95, 0.01) var damage_reduction: float = 0.0


func reset_health() -> void:
	current_hp = maxf(max_hp, 1.0)


func get_armor_by_part(part: ArmorPart.Type) -> float:
	match part:
		ArmorPart.Type.BELT:
			return maxf(belt_armor, 0.0)
		ArmorPart.Type.DECK:
			return maxf(deck_armor, 0.0)
		ArmorPart.Type.BOW:
			return maxf(bow_armor, 0.0)
		ArmorPart.Type.STERN:
			return maxf(stern_armor, 0.0)
		ArmorPart.Type.SUPERSTRUCTURE:
			return maxf(superstructure_armor, 0.0)
	return maxf(belt_armor, 0.0)
