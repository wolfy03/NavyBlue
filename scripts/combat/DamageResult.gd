class_name DamageResult
extends RefCounted

var resolved: bool = false
var hit_info: HitInfo
var penetration_result: int = PenetrationResolver.Result.NON_PENETRATED
var impact_angle_degrees: float = 0.0
var armor: float = 0.0
var effective_armor: float = 0.0
var raw_damage: float = 0.0
var applied_damage: float = 0.0
