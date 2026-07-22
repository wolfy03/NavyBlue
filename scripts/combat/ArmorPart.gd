class_name ArmorPart
extends RefCounted

enum Type {
	BELT,
	DECK,
	BOW,
	STERN,
	SUPERSTRUCTURE,
}


static func get_part_name(part: Type) -> StringName:
	match part:
		Type.BELT:
			return &"BELT"
		Type.DECK:
			return &"DECK"
		Type.BOW:
			return &"BOW"
		Type.STERN:
			return &"STERN"
		Type.SUPERSTRUCTURE:
			return &"SUPERSTRUCTURE"
	return &"UNKNOWN"
