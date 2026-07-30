# Projectile Migration

## Baseline

Shell projectiles use `Projectile.gd`; torpedoes inherit
`WeaponProjectileBase`; aircraft payloads instantiate projectile scenes through
`AircraftWeaponController`. Launchers currently share
`ProjectileLaunchContext` but not one typed root.

## Implemented Contract

Gameplay projectiles use one of two explicit typed roots:

- `ProjectileBase` (`Node3D`) for manually integrated shell and bomb flight
- `WeaponProjectileBase` (`RigidBody3D`) for Jolt-integrated torpedoes

Both expose the same typed lifecycle:

1. `configure(data, services)`
2. `launch(context)`
3. `reset_for_pool()`

The shared state behind that API is `ProjectileLifecycle`, a `RefCounted`
component used by both roots. It owns configuration, launch state,
`ProjectileRuntimeState`, injected services, and the one-shot impact guard.
Manual trajectory and RigidBody state remain on their respective roots.

The split is deliberate. Making the shared base a `RigidBody3D` changed the
existing shell contract and failed `CombatVisibilityTest`; converting torpedoes
to manual `Node3D` integration would change collision and guidance behavior.
`ProjectileFactory` performs explicit typed casts to the two roots without
method-name probing and returns `ProjectileCreationResult`. Pool acquisition
returns `PoolAcquireResult`; instantiate fallback is an explicit factory
policy. Failed pool release resets and frees the instance, with one warning per
service lifetime.

`ProjectileFactory` is the only gameplay creation entry point and
`ProjectilePoolService` is the only ObjectPool boundary.

## Migration Order

1. introduce base, runtime state, impact result, and factory
2. migrate shell
3. migrate bomb
4. migrate torpedo
5. remove dynamic setup and launch probes
6. verify pool reset and one-shot impact signals

## Completed

- shell, aircraft bomb, and torpedo launchers use `ProjectileFactory`
- removed `setup_projectile_data` and `launch_with_context`
- source actor, team, weapon, target, velocity, timers, collision state, and
  service references reset on pool recycle
- typed `ProjectileImpactResult` feeds `CombatEffectPresenter`
- shell, bomb, and torpedo impact paths use `mark_impact_once()`
- `ProjectileCreationResult` distinguishes argument, acquire, root,
  configuration, and launch failures
