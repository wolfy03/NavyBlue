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

- `BattleServices` uses `callv` for Autoload signals and ObjectPool because the
  existing Autoload scripts do not expose globally named service interfaces.
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

- Projectile, weapon-mount, ship-damage, effect, and fleet-AI classes still
  contain legacy direct EventBus or ObjectPool discovery. Moving these safely
  requires extending the battle-service injection chain through every pooled
  projectile and mount scene.
- `BattleScene`, menu, and meta-flow code remain valid composition roots and
  still resolve Autoloads directly.
- RunManager has no globally named typed interface, so
  `PlayerShipResolver` and `RunShipStateRestorer` use dynamic calls against an
  injected Node at the serialization boundary.
- Projectile scenes still use a dynamic setup contract because the current
  shell, bomb, and torpedo implementations do not share one typed base.
- Domain-specific debug exports outside the refactored command, spawn, and
  aircraft-release paths have not yet migrated to `BattleDebugSettings`.
- The full 36,000-frame 10v10 and battle AI endurance tests exceed the current
  validation window and remain required before a performance-focused release.
