class_name DamageResult
extends RefCounted

var resolved: bool = false
var hit_info: HitInfo
var target_ship: Node3D
var damage_type: DamageType.Type = DamageType.Type.SHELL_AP
var hit_outcome: HitOutcome.Type = HitOutcome.Type.NONE
# Kept for shell callers and older UI/stat consumers.
var penetration_result: int = PenetrationResolver.Result.NON_PENETRATED
var impact_angle_degrees: float = 0.0
var armor: float = 0.0
var effective_armor: float = 0.0
var raw_damage: float = 0.0
var applied_damage: float = 0.0
var final_damage: float = 0.0
var flooding_triggered := false
