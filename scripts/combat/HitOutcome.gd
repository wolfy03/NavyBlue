extends RefCounted
class_name HitOutcome

enum Type {
	NONE,
	PENETRATED,
	NON_PENETRATED,
	RICOCHET,
	TORPEDO_HIT,
	EXPLOSION_HIT,
	STATUS_DAMAGE,
}


static func from_penetration_result(penetration_result: int) -> Type:
	match penetration_result:
		PenetrationResolver.Result.PENETRATED:
			return Type.PENETRATED
		PenetrationResolver.Result.NON_PENETRATED:
			return Type.NON_PENETRATED
		PenetrationResolver.Result.RICOCHET:
			return Type.RICOCHET
	return Type.NONE


static func from_damage(
		damage_type: DamageType.Type,
		penetration_result: int
) -> Type:
	match damage_type:
		DamageType.Type.SHELL_AP, DamageType.Type.SHELL_HE:
			return from_penetration_result(penetration_result)
		DamageType.Type.TORPEDO:
			return Type.TORPEDO_HIT
		DamageType.Type.EXPLOSION:
			return Type.EXPLOSION_HIT
		DamageType.Type.FIRE, DamageType.Type.FLOODING:
			return Type.STATUS_DAMAGE
	return Type.NONE


static func get_type_name(hit_outcome: Type) -> StringName:
	match hit_outcome:
		Type.PENETRATED:
			return &"PENETRATED"
		Type.NON_PENETRATED:
			return &"NON_PENETRATED"
		Type.RICOCHET:
			return &"RICOCHET"
		Type.TORPEDO_HIT:
			return &"TORPEDO_HIT"
		Type.EXPLOSION_HIT:
			return &"EXPLOSION_HIT"
		Type.STATUS_DAMAGE:
			return &"STATUS_DAMAGE"
	return &"NONE"
