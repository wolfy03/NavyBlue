# Parameter Ownership

| Parameter | Authoritative source |
| --- | --- |
| Sea level | `BattleEnvironment` |
| Battlefield command margins | `BattlefieldRules` |
| Ship formation and spacing | `FleetFormationData` |
| Aircraft formation and loiter | `SquadronData` |
| Dive angle, speed, altitude, target pass | `DiveBomberCombatData` |
| Payload timeout and retries | `AircraftPayloadReleaseSettings` |
| Default player ship | `GameConfig` |
| Active-run player ship | `RunManager` / `NewRunConfig` |
| Test player ship override | `BattleTestConfig` |
| Faction display color | `FactionData` through `FactionPalette` |
| Input bindings | `project.godot` InputMap |
| Battle debug output | `BattleDebugSettings` |

`BattlefieldSettings.sea_level_m` remains only as the serialized bootstrap
value used by `BattleScene` to initialize `BattleEnvironment`. Runtime command,
camera, and aircraft systems read `BattleEnvironment.sea_level_m`.
