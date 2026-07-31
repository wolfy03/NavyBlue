# Weapon Preview Contract

## Cannon range

The player cannon preview renders one line for every preview-available cannon
mount on the controlled player ship. Each line uses the mount's
`WeaponMount.get_runtime_maximum_range_m()`, so runtime range upgrades remain
authoritative.

Disabled, empty, reloading, unaligned, and projectile-blocked mounts remain
visible in red. A mount is green only when its existing current fire readiness
is `READY`. Mounts without cannon data, a positive runtime range, or a valid
muzzle are not rendered.

The aggregate maximum range accessor remains available for manual aim command
compatibility, but presentation code does not use it.

## Relative bearing

Player manual aim stores one hull-relative bearing per ship. Weapon mounts
continue to resolve that world direction through their initial
`base_local_yaw_radians`, traverse arc, and rotation speed. Every preview line
uses the current muzzle transform rather than the requested direction. AI
world-target tracking remains a separate aim mode.

## Presentation lines

Turret range previews and aircraft command paths use a centered unit `BoxMesh`.
`BoxLinePlacement` points local `-Z` at the endpoint, places the root at the
segment midpoint, and scales local Z to the requested world length. The turret
presentation updates at 20 Hz and pools preview scenes by mount instance ID.

Aircraft command paths are command-plane indicators, not predicted flight
trajectories. Both their line and destination marker use the destination
snapshot's command-plane height plus the presentation offset.

## MultiMesh threshold

Squadron selection boxes retain twelve shared `BoxMesh` edges. A `MultiMesh`
implementation should only be considered after profiling shows a meaningful
draw-call cost with at least ten simultaneously selected squadrons. The public
`activate`, `deactivate`, and `set_bounds` contract should remain unchanged.
