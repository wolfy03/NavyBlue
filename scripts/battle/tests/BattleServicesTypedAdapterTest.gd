extends SceneTree

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var settings := BattleDebugSettings.new()
	settings.log_projectile_lifecycle = true
	var services := BattleServices.new()
	services.setup(
		root.get_node_or_null("EventBus"),
		root.get_node_or_null("ObjectPool"),
		root.get_node_or_null("RunManager"),
		root.get_node_or_null("GameManager"),
		null,
		settings
	)
	_check(services.events is BattleEventPublisher, "typed event publisher")
	_check(
		services.projectile_pool is ProjectilePoolService,
		"typed projectile pool service"
	)
	_check(
		services.projectile_factory is ProjectileFactory,
		"typed projectile factory"
	)
	_check(services.run_session is RunSessionReader, "typed run reader")
	_check(services.game_flow is GameFlowService, "typed game flow service")
	_check(
		services.debug_settings == settings,
		"debug settings are injected through BattleServices"
	)
	services.shutdown()
	services.shutdown()
	_check(
		services.debug_settings == null
			and services.projectile_factory.battle_services == null,
		"shutdown is idempotent and releases injected references"
	)
	services.setup(
		root.get_node_or_null("EventBus"),
		root.get_node_or_null("ObjectPool"),
		null,
		null,
		null,
		settings
	)
	_check(
		services.projectile_factory.battle_services == services,
		"services can be configured again after shutdown"
	)
	services.shutdown()
	print(
		"BATTLE_SERVICES_TYPED_ADAPTER_TEST failures=%d"
		% _failures.size()
	)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures.append(label)
	push_error("BATTLE SERVICES: %s" % label)
