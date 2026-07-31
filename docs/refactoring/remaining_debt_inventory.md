# Remaining Debt Inventory

Baseline: `fffe56206ddce1d75f95b29341cdb21f0bb5485a`.

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

- The current release-candidate gate completed 600-frame smoke, 1,800-frame
  extended smoke, 9,000-frame 10v10 seeds 1 and 2, 9,000-frame BattleAI and
  carrier-inclusive 6v6, plus the same four 36,000-frame nightly profiles with
  no final metric failures.
- `BattleTestServices` no longer stores services in SceneTree root metadata.
  A lifecycle host and explicit fixture shutdown removed the prior ObjectDB
  and Resource-in-use warnings from the final 93-entry extended validation
  and 15 standalone regression entrypoints. `TestTeardownAudit` reports no
  projectile, effect, squadron, FleetAI, member callback, or payload-request
  runtime residue after shutdown.
- Warning-path tests still emit their expected diagnostics for pool failure
  and save migration. They do not leave ObjectDB or Resource-use residue.
- Shell/bomb and torpedo roots use separate typed bases because Godot native
  inheritance cannot share one custom root across manual `Node3D` and
  `RigidBody3D` physics without changing established projectile behavior.
- Role suitability is owned by `FleetRoleSuitabilityPolicy`; emergency
  interceptor composition is owned by `EmergencyInterceptorPolicy`.
  `FleetAIController` schedules those policies and applies typed results.
- Targetless ships use the normal targeting cadence, and null-to-null target
  transitions no longer clear navigation or inflate decision metrics.
- Endurance result parsing remains a small text adapter around the existing
  long-run entrypoints. A future typed long-run result writer could replace it
  without changing the test scenarios.
