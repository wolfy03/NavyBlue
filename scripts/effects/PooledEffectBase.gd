extends Node3D
class_name PooledEffectBase

var active := false
var last_activated_msec := 0


func activate(request: EffectRequest) -> void:
	if request == null:
		return
	active = true
	last_activated_msec = Time.get_ticks_msec()
	visible = true
	set_process(true)
	_on_activate(request)


func deactivate() -> void:
	if active:
		_on_deactivate()
	active = false
	reset_for_pool()
	visible = false
	set_process(false)


func reset_for_pool() -> void:
	_on_reset_for_pool()


func is_available() -> bool:
	return not active


func _on_activate(_request: EffectRequest) -> void:
	pass


func _on_deactivate() -> void:
	pass


func _on_reset_for_pool() -> void:
	pass
