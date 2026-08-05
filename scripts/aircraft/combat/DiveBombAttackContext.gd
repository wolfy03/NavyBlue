extends RefCounted
class_name DiveBombAttackContext
## Per-attack-pass planning state shared between a dive-bomb order (AI
## mission or player run) and DiveBombAttackPlanner.
##
## Owns the deterministic accuracy offset for the current pass: rolled once
## per (target identity, attack pass) and held constant through every repath
## re-solve, so the aim never wanders inside a pass; a target change rolls a
## fresh deterministic offset.

var squadron_combat_id := 0
var attack_pass_index := 0
var solution_revision := 0

var pass_dispersion_offset := Vector3.ZERO
## Identity key the current offset was rolled for (ship instance id, or the
## hashed designation for position targets). Zero = not rolled yet.
var dispersion_target_key := 0

## Diagnostics for the mission debug snapshot.
var target_resolve_count := 0
var target_reacquire_count := 0


func next_revision() -> int:
	solution_revision += 1
	return solution_revision


func reset_for_new_pass() -> void:
	attack_pass_index += 1
	pass_dispersion_offset = Vector3.ZERO
	dispersion_target_key = 0
