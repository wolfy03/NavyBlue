extends Resource
class_name ShipSpawnData

@export var ship_id: StringName
@export var team: StringName
@export var fleet_id: StringName
@export var display_name: String
@export var spawn_marker_id: StringName
@export var is_player := false

@export_category("Transform")
@export var use_explicit_transform := false
@export var explicit_transform := Transform3D.IDENTITY

@export_category("Visual")
@export var use_color_override := false
@export var color_override := Color.WHITE


func validate(expect_player: bool, label: String) -> PackedStringArray:
	var errors := PackedStringArray()
	if is_player != expect_player:
		errors.append("%s must set is_player=%s." % [label, expect_player])
	if not expect_player:
		if ship_id.is_empty():
			errors.append("%s is missing ship_id." % label)
		elif not ShipDatabase.SHIP_PATHS.has(String(ship_id)):
			errors.append(
				"%s has unsupported ship_id '%s'."
				% [label, ship_id]
			)
	elif not ship_id.is_empty() \
			and not ShipDatabase.SHIP_PATHS.has(String(ship_id)):
		errors.append(
			"%s has unsupported optional player ship_id '%s'."
			% [label, ship_id]
		)
	if team.is_empty():
		errors.append("%s is missing team." % label)
	elif team not in [
		FactionRelations.PLAYER,
		FactionRelations.ALLY,
		FactionRelations.ENEMY,
		FactionRelations.NEUTRAL,
	]:
		errors.append("%s has unsupported team '%s'." % [label, team])
	if display_name.is_empty() and spawn_marker_id.is_empty():
		errors.append("%s requires display_name or spawn_marker_id." % label)
	return errors


func resolve_transform(marker: Node3D = null) -> Transform3D:
	if use_explicit_transform:
		return explicit_transform
	return marker.global_transform if marker != null else Transform3D.IDENTITY
