extends SceneTree

const DEFAULT_FACTION_PALETTE: FactionPalette = preload(
	"res://resources/factions/default_faction_palette.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleServices.new()
	var missing_errors := services.validate_dependencies(null, null, null)
	_check(
		missing_errors.size() == 3,
		"all required dependencies are reported"
	)
	var valid_errors := services.validate_dependencies(
		root.get_node_or_null("EventBus"),
		root.get_node_or_null("ObjectPool"),
		DEFAULT_FACTION_PALETTE
	)
	_check(valid_errors.is_empty(), "valid dependencies pass")
	_check(
		services.setup(
			root.get_node_or_null("EventBus"),
			root.get_node_or_null("ObjectPool"),
			null,
			null,
			DEFAULT_FACTION_PALETTE
		),
		"optional run and game services may be absent"
	)
	services.shutdown()
	services.shutdown()
	_check(
		services.faction_palette == null
			and services.projectile_factory.battle_services == null,
		"shutdown is idempotent"
	)
	print(
		"BATTLE_SERVICES_DEPENDENCY_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("BATTLE SERVICES DEPENDENCY: %s" % label)
