# Endurance Test Plan

## Profiles

- smoke: 600 frames
- extended smoke: 1,800 frames
- seeded battle: 9,000 frames
- full endurance: 36,000 frames

## Chunk Metrics

Capture every 600 frames:

- live ships, aircraft, projectiles, effects, and total nodes
- pending payload releases and orphan AI targets
- ObjectPool acquire/release balance
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

- `BattleEnduranceMetrics` captures group counts, node count, pending payload
  requests, and projectile-pool acquire/release totals.
- `BattleEnduranceRunner` executes physics frames in configurable chunks.
- `BattleEnduranceSmokeTest` runs the battle-loop stage for 600 frames.

The active-combat smoke allows bounded in-flight projectile growth. Cleanup
profiles use the stricter default growth budget after battle teardown.
