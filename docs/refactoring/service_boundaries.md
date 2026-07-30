# Service Boundaries

## Composition

`BattleScene` is the battle composition root. It may resolve Autoload nodes and
construct typed adapters.

## Typed Adapters

- `BattleEventPublisher`: explicit battle event publication
- `ProjectilePoolService`: ObjectPool acquire/release boundary
- `RunSessionReader`: read-only run state access
- `GameFlowService`: battle completion and scene-flow requests

`BattleServices` is a typed aggregate only. Domain code must not call arbitrary
Autoload methods through it.

Projectile creation is exposed by the typed `ProjectileFactory`. Damage and
impact presentation travel through `BattleEventPublisher` to
`CombatEffectPresenter`.

## Allowed Dynamic Calls

Dynamic calls are limited to adapter internals until the existing Autoload
scripts expose globally named interfaces. Save dictionaries and debug snapshots
remain at their serialization/diagnostic boundaries.

Source audit tests enforce that weapon, combat, effect, unit, and AI domain
directories contain no `/root/EventBus` or `/root/ObjectPool` discovery.
