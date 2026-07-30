extends RefCounted
class_name EffectRequest

var position := Vector3.ZERO
var normal := Vector3.UP
var velocity := Vector3.ZERO
var strength := 1.0
var damage_result: DamageResult
var projectile_data: ProjectileData
var hit_outcome := HitOutcome.Type.NONE
var shell_type := ShellStats.ShellType.AP
var end_position := Vector3.ZERO
var rounds_fired := 0
var hit_count := 0
var tracer_interval := 3
