extends Node
class_name DifficultyScaler

@export var base_difficulty := 1.0

func difficulty_for_wave(wave_index: int) -> float:
	return base_difficulty + float(wave_index) * 0.12
