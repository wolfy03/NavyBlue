extends Node

signal ship_spawned(ship)
signal ship_destroyed(ship)
signal projectile_fired(projectile)
signal wave_started(wave_index: int)
signal game_mode_changed(previous_mode: int, current_mode: int)
signal run_started(stage_id: String)
signal run_updated(run_state: Dictionary)
signal run_finished(result: Dictionary)
