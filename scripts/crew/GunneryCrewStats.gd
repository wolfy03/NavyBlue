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
