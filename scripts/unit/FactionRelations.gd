extends RefCounted
class_name FactionRelations

const PLAYER: StringName = &"player"
const ALLY: StringName = &"ally"
const ENEMY: StringName = &"enemy"
const NEUTRAL: StringName = &"neutral"


static func are_hostile(first_team: StringName, second_team: StringName) -> bool:
	if first_team == second_team:
		return false
	if first_team == NEUTRAL or second_team == NEUTRAL:
		return false
	var first_is_friendly := first_team == PLAYER or first_team == ALLY
	var second_is_friendly := second_team == PLAYER or second_team == ALLY
	return (first_is_friendly and second_team == ENEMY) \
		or (second_is_friendly and first_team == ENEMY)
