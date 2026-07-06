extends Node
class_name WaveSystem

var current_wave := 0

func start_wave(index: int) -> void:
	current_wave = index
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").wave_started.emit(index)

