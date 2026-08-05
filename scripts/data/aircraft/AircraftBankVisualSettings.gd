extends Resource
class_name AircraftBankVisualSettings
## Visual-only banking of the aircraft model during horizontal turns.
##
## Applied exclusively to the aircraft's %VisualRoot child: the physics
## root, collision shape and weapon transforms never roll, so flight
## behaviour and hit detection are unaffected by any of these values.

## Bank angle the model shows at (and beyond) the full-bank turn rate.
@export_range(0.0, 85.0, 0.5)
var maximum_bank_angle_degrees := 40.0

## Horizontal turn rate that maps to the maximum bank angle; slower turns
## bank proportionally less.
@export var turn_rate_for_full_bank_deg_sec := 40.0

## How fast the model rolls INTO a turn, degrees of bank per second.
@export var bank_response_speed_deg_sec := 90.0

## How fast the model rolls back toward level when the turn eases off.
@export var bank_return_speed_deg_sec := 55.0

## Below this horizontal speed the model always returns to level: taxiing,
## near-stall formation shuffling and vertical dives must not wobble.
@export var minimum_horizontal_speed_mps := 15.0
