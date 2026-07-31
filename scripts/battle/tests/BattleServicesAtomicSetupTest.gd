extends SceneTree

const DEFAULT_FACTION_PALETTE: FactionPalette = preload(
	"res://resources/factions/default_faction_palette.tres"
)

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var services := BattleServices.new()
	var invalid_pool := Node.new()
	_check(
		not services.setup(
			root.get_node_or_null("EventBus"),
			invalid_pool,
			null,
			null,
			DEFAULT_FACTION_PALETTE
		),
		"collaborator setup failure is reported"
	)
	_check(
		not services.is_configured()
			and not services.events.is_configured()
			and not services.projectile_pool.is_configured()
			and not services.projectile_factory.is_configured()
			and services.faction_palette == null,
		"failed setup rolls back every collaborator"
	)
	_check(
		services.setup(
			root.get_node_or_null("EventBus"),
			root.get_node_or_null("ObjectPool"),
			null,
			null,
			DEFAULT_FACTION_PALETTE
		) and services.is_configured(),
		"valid setup configures all required collaborators"
	)
	services.shutdown()
	services.shutdown()
	_check(not services.is_configured(), "shutdown is idempotent")
	print("BATTLE_SERVICES_ATOMIC_SETUP_TEST failures=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("BATTLE SERVICES ATOMIC SETUP: %s" % label)
