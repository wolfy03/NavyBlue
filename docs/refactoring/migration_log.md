# Migration Log

## Baseline

- Recorded the scene, autoload, class, caller, dynamic-call, and test topology.
- Captured a passing Godot 4.7 parse and high-signal regression suite.

## Typed Foundations

- Added battle environment, rules, and debug resources.
- Added typed spawn data, request, resolution, creation, and stage result types.
- Added faction display resources and explicit test configuration.
- Added destination tracking, payload settings/context/result, and pure dive
  release policy/result types.

## Player Commands

- Kept `PlayerInputManager` as the scene-facing command-mode router.
- Moved typed ship selection, ship commands, world picking, and fleet placement
  into `SelectionCoordinator`, `ShipCommandController`,
  `WorldPointerResolver`, and `FleetFormationPlanner`.
- Added `AircraftCommandController` as the routing adapter for the existing
  aircraft selection and carrier targeting components.
- Removed dynamic ShipUnit command calls from player input and typed the camera
  selection-provider contract.

## Typed Stage Spawning

- Replaced StageData spawn dictionaries with typed `ShipSpawnData` resources.
- Split player resolution, stage interpretation, ship construction, and run
  restore into `PlayerShipResolver`, `StageSpawnCoordinator`, `ShipFactory`,
  and `RunShipStateRestorer`.
- Reduced `SpawnSystem` to a scene-compatible facade configured by
  `BattleScene`.
- Replaced Dictionary stage results with `StageSpawnResult`.
- Removed production `StageData.test_player_ship_override`; explicit debug
  stage overrides are translated to `BattleTestConfig` at the composition root.
- Moved faction colors to `FactionData` resources.

## Aircraft Squadron

- Extracted destination serial state to `SquadronDestinationTracker`.
- Extracted formation travel, direct flight, arrival, and loiter behavior to
  `SquadronMovementController`.
- Extracted aircraft creation, launch activation, and node release to
  `SquadronLifecycleController`.
- Extracted request IDs, timeout/cancellation, projectile completion, and pass
  results to `AircraftPayloadReleaseCoordinator`.
- Replaced release dictionaries at the public boundary with typed context,
  request result, and pass result objects.

## Dive Attack

- Extracted altitude-window decisions to the pure `DiveReleasePolicy`.
- Moved timeout, retry, and completion-wait tuning to
  `AircraftPayloadReleaseSettings`.
- Replaced Dictionary attack results with `DiveAttackResult`.
- Removed the unused `begin_dive` compatibility wrapper. All callers now pass
  an explicit `DiveControlSource` to `begin_dive_with_source`.
- Migrated tests away from removed whole-squadron release counters and private
  request dictionaries.

## Composition Root

- Added `BattleServices` as the battle-scoped Autoload adapter.
- `BattleScene` resolves Autoloads once and injects the adapter through
  `SpawnSystem`, `ShipFactory`, `ShipUnit`, `CarrierAirGroup`,
  `AircraftSquadron`, and `AircraftUnit`.
- Removed `/root/EventBus` and `/root/ObjectPool` discovery from the aircraft
  domain.
- Injected battle services into `BattleStateController` and removed its direct
  RunManager, EventBus, and GameManager discovery.
- Moved aircraft command margins and water-plane lookup to
  `BattlefieldRules` and `BattleEnvironment`.

## Deliberate Dynamic Boundaries

- Typed service adapters use dynamic calls only against legacy Autoload scripts
  that do not expose globally named interfaces.
- `BattleStateController` invokes RunManager and GameManager through injected
  Node references for the same reason.
- Projectile scene setup remains dynamic because multiple projectile scene
  implementations share a behavioral contract but not a common typed base.

## Verification

- Godot 4.7 editor parse completes without script or resource load errors.
- The recursive resource and scene load audit passes.
- The regression entrypoints for startup, spawning, run restore, command modes,
  aircraft selection and loiter, fighter intercept, dive bombing, carrier
  recovery, projectile launch, and save/load pass.
- Existing non-long-run aircraft, carrier, input, world, weapon, projectile,
  and AI tests pass.
- The 6v6 fleet AI long-run test passes with a 600-frame smoke override.
- `OceanVisual.gd` and its wave implementation remain unchanged.
- Save version 2 remains unchanged and version compatibility tests pass.

## Remaining Migration Debt

- `BattleScene`, menu, and meta-flow code remain valid composition roots and
  still resolve Autoloads directly.
- RunManager has no globally named typed interface, so
  `PlayerShipResolver` and `RunShipStateRestorer` use dynamic calls against an
  injected Node at the serialization boundary.
- Manual shell/bomb integration and RigidBody torpedo integration use separate
  typed projectile roots to preserve their established physics contracts.
- Some optional effect and ocean integrations retain documented behavioral
  calls at external presentation boundaries.
- The 36,000-frame nightly gate is now executable per profile and seed through
  the PowerShell runner; artifacts remain ignored release outputs.

## Stabilization Pass

- Added idempotent `setup`/`shutdown` contracts and explicit signal disconnects
  to squadron, payload, command, and spawn collaborators.
- Added `ShipSpawnData`, `StageData`, `FactionData`, and `FactionPalette`
  validation and fail-fast stage spawning.
- Made `SquadronData.payload_release_settings` the single payload
  infrastructure settings owner.
- Replaced broad battle service calls with `BattleEventPublisher`,
  `ProjectilePoolService`, `RunSessionReader`, and `GameFlowService`.
- Added typed shell/bomb and torpedo projectile roots, `ProjectileFactory`,
  runtime reset state, and typed impact results.
- Added typed damage requests/results and separated impact presentation into
  `CombatEffectPresenter` and `EffectFactory`.
- Added common `WeaponRuntimeState`; mount-specific traverse, ballistics, and
  salvo rules remain in their existing concrete mounts.
- Removed direct EventBus/ObjectPool discovery from weapon, combat, effect,
  ship, and AI domain directories.
- Split FleetAI perception, target scoring, tactical-position planning, and
  order dispatch behind typed collaborators while preserving existing update
  intervals and tactical policy.
- Added typed boundary, lifecycle, Resource immutability, projectile contract,
  and endurance smoke tests.

## Fleet, Projectile, And Effect Lifecycle Pass

- Moved FleetAI targeting, emergency, role, tactical, lifecycle, scheduling,
  and debug cadence values from `FleetAIController` to `FleetAISettings`.
- Converted difficulty cadence values to multipliers while preserving the
  previous easy, normal, and hard effective timings.
- Added typed `FleetTargetRecommendation`, `FleetTacticalDecision`,
  `FleetMemberOrder`, and `FleetEngagementPolicy`.
- Replaced dynamic FleetAI recommendation calls and Dictionary field access.
- Added an explicit member exit callback registry and idempotent event/member
  disconnection during FleetAI shutdown.
- Added `ProjectileLifecycle` shared by the manual and RigidBody projectile
  roots without changing their physics inheritance.
- Added typed pool acquisition and projectile creation results, explicit
  instantiate fallback, and safe failed-release cleanup.
- Made `BattleServices.setup()` validate required dependencies and return a
  success result.
- Migrated internal shell, torpedo, and fighter tracer scenes to
  `PooledEffectBase` and typed `EffectRequest` activation.
- Added `TestTeardownAudit`; moved test-scoped battle services from root
  metadata to an exit-aware host node.
- Extended endurance metrics and added 1,800/9,000/36,000 frame profiles.
- Added explicit `BattleScene.shutdown()` orchestration for FleetAI, spawning,
  effects, and battle-scoped services.
- Removed the unused `ShipImpactEffectService`; typed combat effect requests
  now flow through `CombatEffectController` and `EffectFactory`.
- Updated the 10v10 endurance fixture to inject `BattleServices` and register
  projectile and aircraft roots before creating combat units.
- Completed 600-frame smoke, 1,800-frame extended smoke, two 9,000-frame
  10v10 seeds, and 9,000-frame BattleAI and carrier-inclusive 6v6 validation
  with zero reported failures.
- The final 93-entry extended validation and 15 standalone regression
  entrypoints completed without ObjectDB leaks, Resource-in-use warnings, or
  unexpected errors.

## Endurance And Lifecycle Stabilization

- Split smoke (600), extended smoke (1,800), seeded (9,000), and nightly
  (36,000) profile definitions behind `EnduranceProfile`.
- Fixed the 15-chunk documentation mismatch: the smoke test had passed a
  hard-coded 120-frame chunk despite the runner's 600-frame default.
- Added baseline, active peak, and post-cleanup endurance snapshots plus
  explicit pool lease/failure/fallback metrics.
- Added `ProjectileCreationOwnership` and one-way `ProjectileLifecycle` state.
- Made projectile factory failure cleanup atomic and prevented fallback
  instances from entering ObjectPool.
- Made `BattleServices.setup()` transactional and expanded ordered,
  idempotent `BattleScene.shutdown()`.
- Extracted role suitability and emergency interceptor composition from
  `FleetAIController` into typed policies without changing scores or limits.
- Audited internal reusable effects; shell impact, torpedo impact, and fighter
  tracer remain the complete `ReusableEffectPool` set.
- Fixed targetless FleetAI evaluation and null-to-null target changes after
  the 36,000-frame 10v10 gate exposed runaway target/navigation updates.
- Completed 36,000-frame 10v10 seeds 1 and 2, BattleAI seed 1, and
  carrier-inclusive 6v6 seed 1 with zero final failures.
- Updated the nightly runner result contract so missing `FLEET_AI_*` summaries
  fail instead of producing an empty metrics object.
