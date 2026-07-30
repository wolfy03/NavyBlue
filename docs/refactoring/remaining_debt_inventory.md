# Remaining Debt Inventory

Baseline: `ad6ce9d9cfc637c9a75828bf94cce58fc4a010ec`.

## Direct Autoload Discovery

Composition roots and application UI may resolve Autoloads. Direct discovery
has been removed from projectile, weapon mount, ship damage, combat effect, and
FleetAI domains. `NoDomainRootAutoloadLookupTest` guards this boundary.

Wave and ocean code is explicitly outside this migration.

## Dynamic Boundaries

- RunManager access is dynamic in player resolution and state restore
- effect pools use a behavioral activate/deactivate contract
- optional ocean integration uses a behavioral sampling contract

## Runtime Ownership Risks

- payload release coordination connects to weapon-controller signals
- lifecycle and movement collaborators retain their owner squadron
- stage collaborators retain factories, services, resources, and scene nodes
- pooled effect implementations still use an activate/deactivate behavior
  contract at the presenter boundary

## Resource Mutation Risks

Stage spawning is request based, ShipData is duplicated before setup, and
projectile runtime modifiers live in `ProjectileRuntimeState` or launch
contexts. Resource validation and immutability tests cover stage and faction
data.

## Debug Ownership

Fleet AI, targeting, carrier AI, ship health, and projectile lifecycle read
development logging flags from `BattleDebugSettings`. UI diagnostics and
gameplay visualization remain separate because they are presentation options,
not domain logging.

## Remaining Work

- Full 10v10 36,000-frame and multi-seed BattleAI endurance profiles remain a
  nightly/local release gate.
- Existing test processes report Godot shutdown ObjectDB/resource-use warnings;
  the endurance harness checks persistent runtime growth, but test-fixture
  teardown can be tightened separately.
- Shell/bomb and torpedo roots use separate typed bases because Godot native
  inheritance cannot share one custom root across manual `Node3D` and
  `RigidBody3D` physics without changing established projectile behavior.
- Fleet tactical policy still resides in `FleetAIController`; perception,
  target scoring, position solving, and dispatch are separated, while a fuller
  typed tactical-decision object remains a future extraction.
