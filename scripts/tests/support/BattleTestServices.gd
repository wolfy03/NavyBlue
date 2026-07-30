extends RefCounted
class_name BattleTestServices

const DEFAULT_FACTION_PALETTE: FactionPalette = preload(
	"res://resources/factions/default_faction_palette.tres"
)

static func create(tree: SceneTree) -> BattleServices:
	if tree == null:
		return BattleServices.new()
	var tree_root := tree.root
	var host := tree_root.get_node_or_null(
		"BattleTestServicesHost"
	) as BattleTestServicesHost
	if host != null and host.services != null:
		return host.services
	if host == null:
		host = BattleTestServicesHost.new()
		host.name = "BattleTestServicesHost"
		tree_root.add_child(host)
	var services := BattleServices.new()
	var configured := services.setup(
		tree_root.get_node_or_null("EventBus"),
		tree_root.get_node_or_null("ObjectPool"),
		tree_root.get_node_or_null("RunManager"),
		tree_root.get_node_or_null("GameManager"),
		DEFAULT_FACTION_PALETTE
	)
	if not configured:
		push_error("BattleTestServices could not configure required services.")
	host.services = services
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
