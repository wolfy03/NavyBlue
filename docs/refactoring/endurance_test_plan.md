# Endurance Test Plan

## Profiles

- `smoke`: 600 frames, fast PR and local regression
- `extended_smoke`: 1,800 frames, merge validation
- seeded endurance: 9,000 frames, multi-seed stability
- nightly endurance: 36,000 frames, release gate

The authoritative profile constants are in `EnduranceProfile.gd`. Profile
frame counts are intentionally unique.

## Phases And Chunks

The battle smoke harness runs:

1. 120 warmup frames
2. baseline snapshot
3. active combat in 600-frame chunks
4. ordered battle shutdown
5. 180 cleanup frames
6. ObjectPool clear
7. post-cleanup snapshot

Every result records requested and executed frames, chunk size, combat and
cleanup chunk counts, warmup and cleanup frames, seed, profile, and initial and
final snapshot counts. Therefore 1,800 active frames produce exactly three
combat chunks.

Metrics distinguish:

- active and pooled projectiles
- active and pooled effects
- pool acquire and release counts
- outstanding pool leases and the active lease registry
- pool acquire and release failures
- instantiate fallbacks, factory-owned releases, foreign releases, and legacy
  direct-pool releases
- pending payload requests, orphan targets, and invalid FleetAI callbacks
- FleetAI perception, targeting, role, tactical-plan, order-dispatch,
  emergency-assignment, invalid-decision, and empty-decision counts

`pool_outstanding_count` means pool acquires minus successful pool releases.
Inactive objects owned by ObjectPool are reported separately and are not
outstanding leases.

## Failure Policy

Active combat may have bounded in-flight growth. Post-cleanup requires zero
active projectiles, active effects, pending payload requests, orphan targets,
callback mismatches, and outstanding pool leases. Missing or malformed JSON,
timeouts, non-zero Godot exits, ObjectDB leaks, resource-in-use diagnostics,
and unexpected errors make the PowerShell runner fail.

## Runner

```powershell
run_endurance_validation.ps1 `
  -Profile extended_smoke `
  -Frames 1800 `
  -Seed 1 `
  -OutputPath artifacts/endurance/local
```

Supported profiles are `smoke`, `extended_smoke`, `6v6`, `10v10`, and
`battle_ai`. Large logs and JSON artifacts live under `artifacts/endurance`
and are ignored by Git.

## Latest Validation

Godot 4.7 validation from the `fffe562` baseline plus this stabilization:

- smoke, 600 frames, seed 1: one 600-frame combat chunk; active peak 19
  projectiles; post-cleanup projectiles/effects/pending/outstanding all zero.
- extended smoke, 1,800 frames, seed 1: three 600-frame combat chunks; active
  peak 31 projectiles and 3 effects; 56 pool acquires and 56 releases;
  post-cleanup projectiles/effects/pending/outstanding all zero.

- 9,000-frame seeded gate: 10v10 seeds 1 and 2, BattleAI seed 1, and
  carrier-inclusive 6v6 seed 1 all completed with zero failures.
- 36,000-frame nightly gate: 10v10 seeds 1 and 2, BattleAI seed 1, and
  carrier-inclusive 6v6 seed 1 all completed with zero failures.

The 36,000-frame 10v10 gate initially exposed a targetless lifecycle defect:
ships with no current target requested an immediate evaluation every physics
frame, and null-to-null target changes repeatedly cleared navigation. This
produced 12,233 target evaluations, 11,787 path calculations, and 11,735
target changes. After making targetless evaluation interval-driven and
null-to-null transitions idempotent, seed 1 completed with 717 evaluations,
116 path calculations, and 17 target changes; seed 2 completed with
711, 125, and 14 respectively.

Nightly summaries and logs are stored under the ignored
`artifacts/endurance/<date>` tree. The runner recognizes both `FLEET_AI_*`
and `AI_LONG_RUN` summary lines; a missing summary makes the result fail.
