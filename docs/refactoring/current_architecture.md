# Current Architecture

Baseline commit: `176fd6c6dbe038b6c4f082af50f717843ae6d70a`.

## Composition

`BattleScene` owns the battle roots (`Ships`, `Aircraft`, `Projectiles`), camera,
HUD, spawning, battle state, input, carrier command, aircraft selection, and
air-combat coordinator nodes. `ship.tscn` owns optional carrier components.

Autoloads are `EventBus`, `GameManager`, `RunManager`, `SceneLoader`,
`SaveManager`, and `ObjectPool`.

## Large Facades

- `PlayerInputManager`: command mode, ship selection, pointer projection,
  formation placement, direct controls, weapons, and carrier/aircraft routing.
- `SpawnSystem`: player resolution, stage interpretation, construction,
  transform resolution, run restore, faction color, and spawn events.
- `AircraftSquadron`: aircraft ownership, movement, loiter, mission routing,
  payload request tracking, fighter targets, recovery, and cleanup.
- `SquadronDiveBombCoordinator`: shared AI/player pass setup, target lock,
  per-aircraft controller aggregation, and post-attack regroup.
- `AircraftDiveBombController`: one aircraft's alignment, fixed-angle dive,
  release window, projectile release, pull-out, and movement ownership.

## Dynamic Boundaries

Most dynamic calls are in input, spawning, optional projectile implementations,
autoload lookup, debug/test code, and ocean extension points. Ocean code is
outside this refactor.

## Baseline Verification

Godot 4.7 editor parse and the battle smoke, stage isolation, player resolution,
command mode, aircraft selection/loiter, fighter intercept, dive-bomb, carrier
lifecycle/save, and weapon initialization/integration tests pass.
