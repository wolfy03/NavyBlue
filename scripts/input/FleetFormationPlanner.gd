extends RefCounted
class_name FleetFormationPlanner


func build_positions(
		center: Vector3,
		ship_count: int,
		data: FleetFormationData
) -> PackedVector3Array:
	var result := PackedVector3Array()
	if ship_count <= 0:
		return result
	var spacing := maxf(data.spacing_m, 1.0) \
		if data != null else 320.0
	var formation_type := data.formation_type \
		if data != null else FleetFormationData.FormationType.GRID
	match formation_type:
		FleetFormationData.FormationType.COLUMN:
			for index in ship_count:
				result.append(
					center + Vector3(
						0.0,
						0.0,
						(float(index) - float(ship_count - 1) * 0.5)
							* spacing
					)
				)
		FleetFormationData.FormationType.LINE_ABREAST:
			for index in ship_count:
				result.append(
					center + Vector3(
						(float(index) - float(ship_count - 1) * 0.5)
							* spacing,
						0.0,
						0.0
					)
				)
		FleetFormationData.FormationType.WEDGE:
			for index in ship_count:
				if index == 0:
					result.append(center)
					continue
				var rank := ceili(float(index) * 0.5)
				var side := -1.0 if index % 2 == 1 else 1.0
				result.append(
					center + Vector3(
						side * float(rank) * spacing,
						0.0,
						float(rank) * spacing
					)
				)
		_:
			var columns := ceili(sqrt(float(ship_count)))
			var rows := ceili(float(ship_count) / float(columns))
			for index in ship_count:
				var column := index % columns
				@warning_ignore("integer_division")
				var row := index / columns
				result.append(
					center + Vector3(
						(float(column) - float(columns - 1) * 0.5)
							* spacing,
						0.0,
						(float(row) - float(rows - 1) * 0.5)
							* spacing
					)
				)
	return result
