extends Resource
class_name FactionData

@export var id: StringName
@export var display_name: String
@export var primary_color: Color = Color.WHITE


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("FactionData.id must not be empty.")
	if display_name.is_empty():
		errors.append("FactionData '%s' requires display_name." % id)
	return errors
