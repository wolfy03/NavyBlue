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
| Fleet targeting, emergency, role, tactical, lifecycle cadence | `FleetAISettings` |
| Fleet reaction delay, decision quality, scheduling multipliers | `AIDifficultyProfile` |

`BattlefieldSettings.sea_level_m` remains only as the serialized bootstrap
value used by `BattleScene` to initialize `BattleEnvironment`. Runtime command,
camera, and aircraft systems read `BattleEnvironment.sea_level_m`.

`FleetAISettings` owns the base scheduling cadence. Difficulty resources only
multiply that cadence. The default base values preserve the former normal
difficulty values (`1.7 / 4.0 / 3.0 / 1.5` seconds), while easy and hard
resources contain equivalent multipliers so the effective timings did not
change during migration.
