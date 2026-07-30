extends Resource
class_name FleetFormationData

enum FormationType {
	GRID,
	COLUMN,
	LINE_ABREAST,
	WEDGE,
}

@export var formation_type: FormationType = FormationType.GRID
@export var spacing_m := 320.0
