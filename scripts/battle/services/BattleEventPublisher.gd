extends RefCounted
class_name BattleEventPublisher

signal battle_started(stage_id: String)
signal battle_cleared(stage_id: String)
signal battle_failed(stage_id: String)
signal projectile_impact(result: ProjectileImpactResult)
signal damage_applied(result: DamageResult)
signal ship_damaged(
	ship: Node,
	amount: float,
	damage_info: Dictionary
)
signal fighter_gun_burst(
	attacker: AircraftUnit,
	target: AircraftUnit,
	rounds_fired: int,
	hit_count: int,
	hit_probability: float
)

var _event_bus: Node


func setup(event_bus: Node) -> void:
	shutdown()
	_event_bus = event_bus
	if _event_bus == null:
		return
	_connect_relay(&"battle_started", _relay_battle_started)
	_connect_relay(&"battle_cleared", _relay_battle_cleared)
	_connect_relay(&"battle_failed", _relay_battle_failed)


func shutdown() -> void:
	if _event_bus != null and is_instance_valid(_event_bus):
		_disconnect_relay(&"battle_started", _relay_battle_started)
		_disconnect_relay(&"battle_cleared", _relay_battle_cleared)
		_disconnect_relay(&"battle_failed", _relay_battle_failed)
	_event_bus = null


func emit_ship_spawned(ship: ShipUnit) -> void:
	_emit(&"ship_spawned", [ship])


func emit_ship_destroyed(ship: ShipUnit) -> void:
	_emit(&"ship_destroyed", [ship])


func emit_ship_damaged(
		ship: ShipUnit,
		amount: float,
		damage_info: Dictionary
) -> void:
	ship_damaged.emit(ship, amount, damage_info)
	_emit(&"ship_damaged", [ship, amount, damage_info])


func emit_projectile_fired(projectile: Node) -> void:
	_emit(&"projectile_fired", [projectile])


func emit_projectile_spawned(projectile: Node3D) -> void:
	_emit(&"projectile_fired", [projectile])


func emit_projectile_impact(result: ProjectileImpactResult) -> void:
	projectile_impact.emit(result)
	_emit(&"projectile_impact", [result])
	if result != null \
			and result.surface_type \
				== ProjectileImpactResult.SurfaceType.WATER:
		emit_projectile_water_impact(
			result.hit_position,
			result.impact_strength
		)


func emit_damage_applied(result: DamageResult) -> void:
	damage_applied.emit(result)
	_emit(&"damage_applied", [result])


func emit_projectile_water_impact(
		position: Vector3,
		strength: float
) -> void:
	_emit(&"projectile_water_impact", [position, strength])


func emit_shell_hit(
		projectile: Node,
		target_ship: Node,
		hit_position: Vector3,
		hit_normal: Vector3,
		result: DamageResult
) -> void:
	_emit(
		&"shell_hit",
		[projectile, target_ship, hit_position, hit_normal, result]
	)


func emit_torpedo_fired(projectile: Node) -> void:
	_emit(&"torpedo_fired", [projectile])


func emit_torpedo_hit(
		projectile: Node,
		target_ship: ShipUnit,
		result: DamageResult
) -> void:
	_emit(&"torpedo_hit", [projectile, target_ship, result])


func emit_aircraft_spawned(aircraft: AircraftUnit) -> void:
	_emit(&"aircraft_spawned", [aircraft])


func emit_aircraft_destroyed(aircraft: AircraftUnit) -> void:
	_emit(&"aircraft_destroyed", [aircraft])


func emit_squadron_launched(squadron: AircraftSquadron) -> void:
	_emit(&"squadron_launched", [squadron])


func emit_squadron_recovered(squadron: AircraftSquadron) -> void:
	_emit(&"squadron_recovered", [squadron])


func emit_squadron_destroyed(squadron: AircraftSquadron) -> void:
	_emit(&"squadron_destroyed", [squadron])


func emit_air_mission_started(
		squadron: AircraftSquadron,
		target: Node3D
) -> void:
	_emit(&"air_mission_started", [squadron, target])


func emit_air_mission_completed(squadron: AircraftSquadron) -> void:
	_emit(&"air_mission_completed", [squadron])


func emit_air_mission_failed(squadron: AircraftSquadron) -> void:
	_emit(&"air_mission_failed", [squadron])


func emit_aircraft_released_payload(
		aircraft: AircraftUnit,
		projectile: Node
) -> void:
	_emit(&"aircraft_weapon_released", [aircraft, projectile])


func emit_fighter_gun_burst(
		attacker: AircraftUnit,
		target: AircraftUnit,
		rounds_fired: int,
		hit_count: int,
		hit_probability: float
) -> void:
	fighter_gun_burst.emit(
		attacker,
		target,
		rounds_fired,
		hit_count,
		hit_probability
	)
	_emit(
		&"fighter_gun_burst_fired",
		[attacker, target, rounds_fired, hit_count, hit_probability]
	)


func emit_aircraft_gun_hit(
		attacker: AircraftUnit,
		target: AircraftUnit,
		damage: float
) -> void:
	_emit(&"aircraft_gun_hit", [attacker, target, damage])


func emit_flooding_started(ship: Node, duration_seconds: float) -> void:
	_emit(&"flooding_started", [ship, duration_seconds])


func emit_flooding_ended(ship: Node) -> void:
	_emit(&"flooding_ended", [ship])


func emit_battle_started(stage_id: String) -> void:
	_emit(&"battle_started", [stage_id])


func emit_battle_cleared(stage_id: String) -> void:
	_emit(&"battle_cleared", [stage_id])


func emit_battle_failed(stage_id: String) -> void:
	_emit(&"battle_failed", [stage_id])


func _emit(signal_name: StringName, arguments: Array) -> void:
	if _event_bus == null or not is_instance_valid(_event_bus) \
			or not _event_bus.has_signal(signal_name):
		return
	_event_bus.callv(&"emit_signal", [signal_name] + arguments)


func _connect_relay(signal_name: StringName, callback: Callable) -> void:
	if _event_bus.has_signal(signal_name) \
			and not _event_bus.is_connected(signal_name, callback):
		_event_bus.connect(signal_name, callback)


func _disconnect_relay(signal_name: StringName, callback: Callable) -> void:
	if _event_bus.has_signal(signal_name) \
			and _event_bus.is_connected(signal_name, callback):
		_event_bus.disconnect(signal_name, callback)


func _relay_battle_started(stage_id: String) -> void:
	battle_started.emit(stage_id)


func _relay_battle_cleared(stage_id: String) -> void:
	battle_cleared.emit(stage_id)


func _relay_battle_failed(stage_id: String) -> void:
	battle_failed.emit(stage_id)
