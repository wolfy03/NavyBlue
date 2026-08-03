extends RefCounted
class_name GunneryWeaponGroupSession

var group_key: StringName = &""
var weapon_data: WeaponData
var projectile_data: ProjectileData
var mounts: Array[CannonMount] = []
var mounted_turret_ids: Array[int] = []

var has_solution := false
var failure_reason: StringName = &""
var ideal_aim_point := Vector3.ZERO
var biased_aim_point := Vector3.ZERO
var fallback_aim_point := Vector3.ZERO
var flight_time_sec := 0.0
var horizontal_range_m := 0.0
var projectile_speed_mps := 0.0
var elevation_rad := 0.0
var gravity_mps2 := 9.8

var current_lead_result: NavalGunLeadResult
var current_salvo: GunnerySalvoSolution
var solution_refresh_elapsed_sec := 0.0
var fire_command_id := 0
var salvo_index := 0

var salvo_active := false
var salvo_started_time_sec := 0.0
var salvo_grouping_window_sec := 0.35
var shells_resolved_in_salvo := 0
var turrets_expected_in_salvo := 0
var resolved_turret_ids: Dictionary = {}
var shots_since_bias := 0


func reset_salvo_session() -> void:
	salvo_active = false
	salvo_started_time_sec = 0.0
	shells_resolved_in_salvo = 0
	turrets_expected_in_salvo = 0
	resolved_turret_ids.clear()
