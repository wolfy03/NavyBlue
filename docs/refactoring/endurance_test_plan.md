# Endurance Test Plan

## Profiles

- smoke: 1,800 frames
- extended smoke: 1,800 frames
- seeded battle: 9,000 frames
- full endurance: 36,000 frames

## Chunk Metrics

Capture every 600 frames:

- live ships, aircraft, projectiles, effects, and total nodes
- pending payload releases and orphan AI targets
- ObjectPool acquire/release balance
- FleetAI decision count and callback registry mismatch count
- average and maximum physics-frame duration
- object and memory growth trend
- repeated warnings and invalid-instance failures

## Failure Policy

Small bounded fluctuations are allowed. Persistent linear growth, requests that
outlive their timeout, stale destroyed targets, pool imbalance growth, or a
battle that cannot finish are failures.

Full endurance remains a separate local or nightly profile; CI uses smoke
profiles.

## Implemented Harness

- `BattleEnduranceMetrics` captures group counts, active typed pooled effects,
  node count, pending payload requests, projectile-pool balance, FleetAI
  decisions, orphan targets, callback mismatches, and chunk frame timing.
- `BattleEnduranceRunner` executes physics frames in configurable chunks.
- `BattleEnduranceSmokeTest` runs the battle-loop stage for 1,800 frames by
  default.
- `run_endurance_validation.ps1 -IncludeExtendedProfiles` runs 6v6 smoke,
  10v10 9,000-frame seeds 1 and 2, and a 9,000-frame BattleAI profile.
- `-IncludeNightly` keeps the separate 36,000-frame local release gate.

The active-combat smoke allows bounded in-flight projectile growth. Cleanup
profiles use the stricter default growth budget after battle teardown.

## Latest Validation

Validated on Godot 4.7 from the `9a1fce5` baseline:

- Battle smoke, 1,800 frames: 15 chunks, node growth 114, projectile growth
  34, effect growth 1, pending payload requests 0, projectile pool balance
  35, FleetAI decisions 51, orphan targets 0, invalid callbacks 0.
- FleetAI 6v6, 1,800 frames: 342.8 simulated FPS, 0 boundary violations,
  0 tactical path failures, 0 failures.
- FleetAI 10v10, 9,000 frames, seed 1: 166.9 simulated FPS,
  max target evaluations 161, max path calculations 24, 0 failures.
- FleetAI 10v10, 9,000 frames, seed 2: 171.1 simulated FPS,
  max target evaluations 162, max path calculations 24, 0 failures.
- BattleAI, 9,000 frames, seed 1: 4 live units, max target evaluations 153,
  max path calculations 31, 0 failures.

The direct 10v10 fixture now builds the same battle service, projectile root,
and aircraft root contracts used by the 6v6 fixture. This prevents fixture-only
weapon launch failures from being mistaken for endurance failures.

The 36,000-frame nightly profile was not run during this pass.
