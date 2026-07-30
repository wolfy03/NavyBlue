# Target Architecture

## Battle Composition Root

`BattleScene` wires `BattleEnvironment`, typed stage spawning, command routing,
HUD, EventBus, RunManager, and ObjectPool references. Domain objects receive
dependencies through setup methods instead of searching `/root`.

## Commands

`PlayerInputManager` remains the scene-compatible router. Ship selection and
orders live in `ShipCommandController`; aircraft commands continue through the
aircraft command facade; pointer projection and formation placement are pure
services.

## Spawning

`StageSpawnCoordinator` interprets typed `ShipSpawnData`. `PlayerShipResolver`
chooses the player ship. `ShipFactory` constructs ships. `RunShipStateRestorer`
applies persisted state. Results are typed.

## Aircraft

`AircraftSquadron` remains the public facade. Destination serials, movement,
lifecycle, and payload release are independent collaborators. Dive attacks use
a pure `DiveReleasePolicy`; projectile outcomes remain authoritative in the
payload release coordinator.

## Autoload Adapter

`BattleServices` is the single battle composition boundary for the existing
Autoload nodes. Domain code receives this object through setup and never
searches `/root`. Dynamic invocation is isolated here until Autoload scripts
gain explicit typed interfaces.

## Serialization

Resources hold design data. Runtime collaborators hold state. Dictionaries are
restricted to save/load and debug snapshot boundaries.
