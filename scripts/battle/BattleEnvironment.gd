extends Node
class_name BattleEnvironment

@export var sea_level_m := 0.0
@export var battlefield_bounds: BattlefieldBounds
@export var rules: BattlefieldRules
@export var debug_settings: BattleDebugSettings


func setup(
		bounds: BattlefieldBounds,
		next_rules: BattlefieldRules,
		next_debug_settings: BattleDebugSettings,
		next_sea_level_m: float
) -> void:
	battlefield_bounds = bounds
	rules = next_rules
	debug_settings = next_debug_settings
	sea_level_m = next_sea_level_m
