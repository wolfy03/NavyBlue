extends Node

signal ship_spawned(ship)
signal ship_destroyed(ship)
signal projectile_fired(projectile)
signal wave_started(wave_index: int)
signal run_started(stage_id: String)
signal run_finished(result: Dictionary)
