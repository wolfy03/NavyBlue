extends RefCounted
class_name DiveBombAccuracyResolver

# DEPRECATED: runtime dive-bomb accuracy now lives in DiveBombAccuracyProfile
# (rolled once per pass by DiveBombAttackPlanner); the targeting preview reads
# the same profile. This legacy formation-count radius is kept only for
# resources/tools that still reference the old dispersion fields.
#
# Resolves the bombing dispersion radius: the circle the preview draws and the
# area bombs actually scatter within. Base accuracy comes from the dive bomber's
# combat data and tightens as more aircraft survive the run.
#
# accuracy_multiplier is the extension hook. Future systems (aircraft type,
# roguelike upgrades, pilot skill) scale accuracy through it without touching
# this formula: values below 1.0 tighten the group, above 1.0 widen it. Callers
# can multiply several modifiers together before passing them in.

const DEFAULT_DISPERSION_RADIUS_M := 90.0


func resolve_dispersion_radius_m(
		data: DiveBomberCombatData,
		alive_aircraft_count: int,
		accuracy_multiplier: float = 1.0
) -> float:
	var multiplier := maxf(accuracy_multiplier, 0.0)
	if data == null:
		return DEFAULT_DISPERSION_RADIUS_M * multiplier
	var extra_aircraft := maxi(alive_aircraft_count - 1, 0)
	var radius := data.base_dispersion_radius_m \
		- float(extra_aircraft) * data.dispersion_reduction_per_extra_aircraft_m
	radius = maxf(radius, data.minimum_dispersion_radius_m)
	return maxf(radius * multiplier, 0.0)
