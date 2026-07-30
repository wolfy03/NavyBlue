# Remaining Debt Inventory

Baseline: `9a1fce593c51278905391338e4c42bde12123398`.

## Direct Autoload Discovery

Composition roots and application UI may resolve Autoloads. Direct discovery
has been removed from projectile, weapon mount, ship damage, combat effect, and
FleetAI domains. `NoDomainRootAutoloadLookupTest` guards this boundary.

Wave and ocean code is explicitly outside this migration.

## Dynamic Boundaries

- RunManager access is dynamic in player resolution and state restore
- optional ocean integration uses a behavioral sampling contract

## Runtime Ownership Risks

- payload release coordination connects to weapon-controller signals
- lifecycle and movement collaborators retain their owner squadron
- stage collaborators retain factories, services, resources, and scene nodes
- ocean ripple/splash integration remains behavioral because it is outside the
  internal combat-effect pool

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
- The current release-candidate gate completed 1,800-frame battle/6v6 smoke,
  9,000-frame 10v10 seeds 1 and 2, and a 9,000-frame BattleAI seed with no
  reported metric failures.
- `BattleTestServices` no longer stores services in SceneTree root metadata.
  A lifecycle host and explicit fixture shutdown removed the prior ObjectDB
  and Resource-in-use warnings from the final 83-entry extended validation
  run. `TestTeardownAudit` reports no projectile, effect, squadron, FleetAI,
  member callback, or payload-request runtime residue after shutdown.
- Warning-path tests still emit their expected diagnostics for pool failure
  and save migration. They do not leave ObjectDB or Resource-use residue.
- Shell/bomb and torpedo roots use separate typed bases because Godot native
  inheritance cannot share one custom root across manual `Node3D` and
  `RigidBody3D` physics without changing established projectile behavior.
- Role suitability and interceptor composition are still calculated in
  `FleetAIController`. Target hysteresis and attacker saturation moved to
  `FleetEngagementPolicy`; recommendations, decisions, and member orders are
  typed.
