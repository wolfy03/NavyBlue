extends RefCounted
class_name BattleTestServices


static func create(tree: SceneTree) -> BattleServices:
	if tree == null:
		return BattleServices.new()
	var tree_root := tree.root
	var existing: Variant = tree_root.get_meta(&"battle_test_services") \
		if tree_root.has_meta(&"battle_test_services") else null
	if existing is BattleServices:
		return existing as BattleServices
	var services := BattleServices.new()
	services.setup(
		tree_root.get_node_or_null("EventBus"),
		tree_root.get_node_or_null("ObjectPool"),
		tree_root.get_node_or_null("RunManager"),
		tree_root.get_node_or_null("GameManager"),
		null
	)
	tree_root.set_meta(&"battle_test_services", services)
	var presenter := tree_root.get_node_or_null(
		"BattleTestCombatEffectPresenter"
	) as CombatEffectPresenter
	if presenter == null:
		presenter = CombatEffectPresenter.new()
		presenter.name = "BattleTestCombatEffectPresenter"
		tree_root.add_child(presenter)
	var effect_controller := tree_root.get_node_or_null(
		"CombatEffectController"
	) as CombatEffectController
	if effect_controller == null:
		effect_controller = tree.get_first_node_in_group(
			&"combat_effect_controller"
		) as CombatEffectController
	if effect_controller != null:
		effect_controller.setup(services.events)
	presenter.setup(effect_controller, services.events)
	return services
