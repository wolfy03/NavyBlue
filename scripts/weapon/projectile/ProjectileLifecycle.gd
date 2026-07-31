extends RefCounted
class_name ProjectileLifecycle

enum State {
	UNCONFIGURED,
	CONFIGURED,
	LAUNCHED,
	IMPACTED,
	RELEASED,
}

var projectile_data: ProjectileData
var launch_context: ProjectileLaunchContext
var battle_services: BattleServices
var runtime_state := ProjectileRuntimeState.new()
var state := State.UNCONFIGURED

var configured: bool:
	get:
		return state in [State.CONFIGURED, State.LAUNCHED, State.IMPACTED]
var launched: bool:
	get:
		return state in [State.LAUNCHED, State.IMPACTED]
var impact_emitted: bool:
	get:
		return state == State.IMPACTED


func configure(data: ProjectileData, services: BattleServices) -> bool:
	reset()
	if data == null or services == null:
		return false
	projectile_data = data
	battle_services = services
	runtime_state = ProjectileRuntimeState.new()
	state = State.CONFIGURED
	return true


func begin_launch(context: ProjectileLaunchContext) -> bool:
	if state != State.CONFIGURED or context == null:
		return false
	launch_context = context
	state = State.LAUNCHED
	runtime_state.active = true
	return true


func mark_impact_once() -> bool:
	if state != State.LAUNCHED:
		return false
	state = State.IMPACTED
	runtime_state.impact_resolved = true
	return true


func set_creation_ownership(
		ownership: ProjectileCreationOwnership.Type
) -> void:
	runtime_state.creation_ownership = ownership


func get_creation_ownership() -> ProjectileCreationOwnership.Type:
	return runtime_state.creation_ownership


func mark_released() -> bool:
	if state not in [State.CONFIGURED, State.LAUNCHED, State.IMPACTED]:
		return false
	state = State.RELEASED
	runtime_state.active = false
	return true


func reset() -> void:
	projectile_data = null
	launch_context = null
	battle_services = null
	runtime_state = ProjectileRuntimeState.new()
	state = State.UNCONFIGURED
