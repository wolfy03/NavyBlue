extends RefCounted
class_name ProjectileLifecycle

var projectile_data: ProjectileData
var launch_context: ProjectileLaunchContext
var battle_services: BattleServices
var runtime_state: ProjectileRuntimeState

var configured := false
var launched := false
var impact_emitted := false


func configure(data: ProjectileData, services: BattleServices) -> bool:
	reset()
	if data == null or services == null:
		return false
	projectile_data = data
	battle_services = services
	runtime_state = ProjectileRuntimeState.new()
	configured = true
	return true


func begin_launch(context: ProjectileLaunchContext) -> bool:
	if not configured or context == null:
		return false
	launch_context = context
	launched = true
	runtime_state.active = true
	return true


func mark_impact_once() -> bool:
	if impact_emitted:
		return false
	impact_emitted = true
	if runtime_state != null:
		runtime_state.impact_resolved = true
	return true


func reset() -> void:
	projectile_data = null
	launch_context = null
	battle_services = null
	runtime_state = ProjectileRuntimeState.new()
	configured = false
	launched = false
	impact_emitted = false
