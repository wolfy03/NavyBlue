extends Resource
class_name GunneryCrewStats
## Per-ship gunnery crew proficiency. All skills are normalized 0..1 and
## default to the temporary mid value until a full crew system exists.
## GunneryAccuracyResolver is the single consumer that maps these skills to
## error multipliers.

@export_range(0.0, 1.0)
var rangefinding_skill := 0.5

@export_range(0.0, 1.0)
var target_tracking_skill := 0.5

@export_range(0.0, 1.0)
var fire_control_skill := 0.5

@export_range(0.0, 1.0)
var gun_laying_skill := 0.5

@export_range(0.0, 1.0)
var salvo_correction_skill := 0.5


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var skills := {
		"rangefinding_skill": rangefinding_skill,
		"target_tracking_skill": target_tracking_skill,
		"fire_control_skill": fire_control_skill,
		"gun_laying_skill": gun_laying_skill,
		"salvo_correction_skill": salvo_correction_skill,
	}
	for property_name: String in skills:
		var value := float(skills[property_name])
		if is_nan(value) or is_inf(value) \
				or value < 0.0 or value > 1.0:
			errors.append("%s must be within 0..1." % property_name)
	return errors
