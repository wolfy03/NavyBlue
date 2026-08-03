extends Node

# Signals on this global bus are emitted by other nodes via
# get_node("/root/EventBus").<signal>.emit(...), so GDScript cannot see the
# emissions locally and would flag every one as UNUSED_SIGNAL. Suppress that
# category for the whole bus so real warnings elsewhere are not buried.
@warning_ignore_start("unused_signal")

signal ship_spawned(ship)
signal ship_destroyed(ship)
signal ship_damaged(ship, amount: float, damage_info)
signal projectile_fired(projectile)
signal projectile_water_impact(position: Vector3, strength: float)
signal projectile_impact(result)
signal damage_applied(result)
signal shell_hit(
	projectile,
	target_ship,
	hit_position: Vector3,
	hit_normal: Vector3,
	result
)
signal torpedo_fired(torpedo)
signal torpedo_hit(torpedo, target_ship, result)
signal aircraft_spawned(aircraft)
signal aircraft_destroyed(aircraft)
signal squadron_launched(squadron)
signal squadron_recovered(squadron)
signal squadron_destroyed(squadron)
signal air_mission_started(squadron, target)
signal aircraft_weapon_released(aircraft, projectile)
signal fighter_gun_burst_fired(
	attacker,
	target,
	rounds_fired: int,
	hit_count: int,
	hit_probability: float
)
signal aircraft_gun_hit(attacker, target, damage: float)
signal air_mission_completed(squadron)
signal air_mission_failed(squadron)
signal flooding_started(ship, duration_seconds: float)
signal flooding_ended(ship)
signal battle_started(stage_id: String)
signal battle_cleared(stage_id: String)
signal battle_failed(stage_id: String)
signal wave_started(wave_index: int)
signal game_mode_changed(previous_mode: int, current_mode: int)
signal run_started(stage_id: String)
signal run_updated(run_state: Dictionary)
signal run_finished(result: Dictionary)
signal reward_selected(reward_id: String)

@warning_ignore_restore("unused_signal")
