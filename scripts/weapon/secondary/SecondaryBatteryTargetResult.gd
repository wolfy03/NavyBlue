extends RefCounted
class_name SecondaryBatteryTargetResult

var target: ShipUnit
var score := 0.0
var candidate_count := 0
var engaging_mount_count := 0
var contexts: Array[SecondaryBatteryTargetContext] = []

