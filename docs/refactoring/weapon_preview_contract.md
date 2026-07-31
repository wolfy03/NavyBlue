# Weapon Preview Contract

## Cannon range

The player cannon preview uses the maximum runtime range among operational
cannon mounts. A mount is operational when it has weapon data, remains enabled,
has ammunition when ammunition is finite, has a projectile source, and has a
positive runtime range.

`WeaponMount.get_runtime_maximum_range_m()` is shared by fire readiness and the
preview. Runtime range upgrades therefore affect both paths. Reloading does not
hide a mount from the preview because it does not change the weapon's range.

The project does not currently expose player-selectable cannon groups. If that
feature is added, `ShipCombat.get_player_cannon_preview_mount()` is the boundary
that must be narrowed to the selected group.

## Relative bearing

Player manual aim stores one hull-relative bearing per ship. Weapon mounts
continue to resolve that world direction through their initial
`base_local_yaw_radians`, traverse arc, and rotation speed. AI world-target
tracking remains a separate aim mode.

## Presentation lines

The cannon range preview and aircraft command path use a centered unit
`BoxMesh`. `BoxLinePlacement` points local `-Z` at the endpoint, places the root
at the segment midpoint, and scales local Z to the requested world length.

Aircraft command paths are command-plane indicators, not predicted flight
trajectories. Both their line and destination marker use the destination
snapshot's command-plane height plus the presentation offset.

## MultiMesh threshold

Squadron selection boxes retain twelve shared `BoxMesh` edges. A `MultiMesh`
implementation should only be considered after profiling shows a meaningful
draw-call cost with at least ten simultaneously selected squadrons. The public
`activate`, `deactivate`, and `set_bounds` contract should remain unchanged.
