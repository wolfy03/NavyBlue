extends RefCounted
class_name AircraftTorpedoReleaseResult

# Outcome of one release pass over a squadron's surviving aircraft.
# `resolved_aircraft_ids` covers every aircraft the pass finished with (released
# or permanently unable to release, e.g. no payload); the controller marks these
# so they are not revisited. `released_aircraft_ids` is the subset that actually
# dropped a torpedo this pass.

var attempted := 0
var released := 0
var failed := 0
var failure_reasons: Array[StringName] = []
var released_aircraft_ids: Array[int] = []
var resolved_aircraft_ids: Array[int] = []
