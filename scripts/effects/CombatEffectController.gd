extends Node3D
class_name CombatEffectController

@export var shell_impact_scene: PackedScene = preload(
	"res://scenes/effects/shell_ship_impact_effect.tscn"
)
@export var torpedo_impact_scene: PackedScene = preload(
	"res://scenes/effects/torpedo_ship_impact_effect.tscn"
)
@export var fighter_tracer_scene: PackedScene = preload(
	"res://scenes/effects/fighter_tracer_effect.tscn"
)
@export_range(1, 96, 1, "or_greater") var shell_pool_size := 32
@export_range(1, 64, 1, "or_greater") var torpedo_pool_size := 16
@export_range(1, 128, 1, "or_greater") var fighter_tracer_pool_size := 32

var _shell_pool: ReusableEffectPool
var _torpedo_pool: ReusableEffectPool
var _fighter_tracer_pool: ReusableEffectPool
var events: BattleEventPublisher


func _ready() -> void:
	add_to_group(&"combat_effect_controller")
	_shell_pool = _create_pool(
		&"ShellImpactPool",
		shell_impact_scene,
		shell_pool_size
	)
	_torpedo_pool = _create_pool(
		&"TorpedoImpactPool",
		torpedo_impact_scene,
		torpedo_pool_size
	)
	_fighter_tracer_pool = _create_pool(
		&"FighterTracerPool",
		fighter_tracer_scene,
		fighter_tracer_pool_size
	)
func setup(next_events: BattleEventPublisher) -> void:
	shutdown()
	events = next_events
	if events != null:
		if not events.fighter_gun_burst.is_connected(
			_on_fighter_gun_burst_fired
		):
			events.fighter_gun_burst.connect(
				_on_fighter_gun_burst_fired
			)


func shutdown() -> void:
	if events != null and events.fighter_gun_burst.is_connected(
		_on_fighter_gun_burst_fired
	):
		events.fighter_gun_burst.disconnect(
			_on_fighter_gun_burst_fired
		)
	events = null


func spawn_shell_impact(
		position: Vector3,
		normal: Vector3,
		incoming_velocity: Vector3,
		hit_outcome: HitOutcome.Type,
		shell_type: ShellStats.ShellType,
		strength: float
) -> Node:
	if _shell_pool == null:
		return null
	return _shell_pool.spawn_effect([
		position,
		normal,
		incoming_velocity,
		hit_outcome,
		shell_type,
		strength,
	])


func spawn_torpedo_impact(
		hit_position: Vector3,
		_surface_position: Vector3,
		normal: Vector3,
		strength: float
) -> Node:
	if _torpedo_pool == null:
		return null
	return _torpedo_pool.spawn_effect([
		hit_position,
		normal,
		strength,
	])


func get_debug_state() -> Dictionary:
	return {
		"active_shell_impacts": (
			_shell_pool.get_active_count() if _shell_pool != null else 0
		),
		"active_torpedo_impacts": (
			_torpedo_pool.get_active_count() if _torpedo_pool != null else 0
		),
		"shell_pool_size": (
			_shell_pool.get_pool_size() if _shell_pool != null else 0
		),
		"torpedo_pool_size": (
			_torpedo_pool.get_pool_size() if _torpedo_pool != null else 0
		),
		"active_fighter_tracers": (
			_fighter_tracer_pool.get_active_count() \
			if _fighter_tracer_pool != null else 0
		),
		"fighter_tracer_pool_size": (
			_fighter_tracer_pool.get_pool_size() \
			if _fighter_tracer_pool != null else 0
		),
	}


func clear_pools() -> void:
	if _shell_pool != null:
		_shell_pool.clear_pool()
	if _torpedo_pool != null:
		_torpedo_pool.clear_pool()
	if _fighter_tracer_pool != null:
		_fighter_tracer_pool.clear_pool()


func _exit_tree() -> void:
	shutdown()


func _on_fighter_gun_burst_fired(
		attacker: AircraftUnit,
		target: AircraftUnit,
		rounds_fired: int,
		hit_count: int,
		_hit_probability: float
) -> void:
	if _fighter_tracer_pool == null \
			or attacker == null \
			or target == null \
			or not is_instance_valid(attacker) \
			or not is_instance_valid(target):
		return
	var gun_data: AircraftGunData
	if attacker.weapon_controller != null \
			and attacker.weapon_controller.weapon_data != null:
		gun_data = attacker.weapon_controller.weapon_data.gun_data
	_fighter_tracer_pool.spawn_effect([
		attacker.global_position,
		target.global_position,
		rounds_fired,
		hit_count,
		gun_data.tracer_interval if gun_data != null else 3,
	])


func _create_pool(
		pool_name: StringName,
		scene: PackedScene,
		size: int
) -> ReusableEffectPool:
	var pool := ReusableEffectPool.new()
	pool.name = pool_name
	pool.setup(scene, size)
	add_child(pool)
	return pool
