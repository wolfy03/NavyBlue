extends Node3D
class_name PooledEffectBase

var active := false
var last_activated_msec := 0
var active_request: EffectRequest


func activate(request: EffectRequest) -> void:
	if request == null:
		return
	active = true
	active_request = request
	last_activated_msec = Time.get_ticks_msec()
	visible = true
	set_process(true)
	set_physics_process(true)
	_on_activate(request)


func deactivate() -> void:
	if active:
		_on_deactivate()
	active = false
	reset_for_pool()
	visible = false
	set_process(false)
	set_physics_process(false)


func reset_for_pool() -> void:
	active_request = null
	scale = Vector3.ONE
	for child in find_children("*", "", true, false):
		var gpu_particles := child as GPUParticles3D
		if gpu_particles != null:
			gpu_particles.emitting = false
			continue
		var cpu_particles := child as CPUParticles3D
		if cpu_particles != null:
			cpu_particles.emitting = false
			continue
		var animation_player := child as AnimationPlayer
		if animation_player != null:
			animation_player.stop()
			continue
		var timer := child as Timer
		if timer != null:
			timer.stop()
			continue
		var audio_player_3d := child as AudioStreamPlayer3D
		if audio_player_3d != null:
			audio_player_3d.stop()
			continue
		var audio_player := child as AudioStreamPlayer
		if audio_player != null:
			audio_player.stop()
	_on_reset_for_pool()


func is_available() -> bool:
	return not active


func _on_activate(_request: EffectRequest) -> void:
	pass


func _on_deactivate() -> void:
	pass


func _on_reset_for_pool() -> void:
	pass
