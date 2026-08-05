extends RefCounted
class_name DiveBombTargetRequest
## One dive-bomb targeting question: "given this designation, what should the
## squadron actually attack?" Built by the AI mission or the player command
## path and answered by DiveBombTargetResolver, so both sides share exactly
## the same selection rules.

enum Source {
	AI,
	PLAYER,
}

var source := Source.AI

## The world position the order designated (clicked ocean point, or the
## assigned ship's position for explicit ship orders).
var designated_world_position := Vector3.ZERO

## Directly designated ship (player clicked a ship, or the AI assigned one).
## Weak: the request must never keep a dead ship alive.
var explicit_target_ref: WeakRef

## Radius (m) around the designation inside which hostile ships are
## auto-acquired. Zero disables radius acquisition.
var acquisition_radius_m := 0.0

var requesting_team: StringName = &"neutral"

## When no ship qualifies: true attacks the designated position itself,
## false yields an INVALID result.
var allow_position_fallback := true

## Reserved for detection-gated targeting: when true, ships that expose an
## is_detected_by_team method must report detected to qualify.
var require_detected_target := false


func get_explicit_target() -> ShipUnit:
	var value: Variant = (
		explicit_target_ref.get_ref()
		if explicit_target_ref != null
		else null
	)
	if value != null and is_instance_valid(value):
		return value as ShipUnit
	return null


func set_explicit_target(ship: ShipUnit) -> void:
	explicit_target_ref = weakref(ship) \
		if ship != null and is_instance_valid(ship) else null
