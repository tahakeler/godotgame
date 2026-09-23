# Active session state

<!-- STATUS -->
Epic: Early Access push
Feature: player-side animation — complete
Task: choosing the next pass
<!-- /STATUS -->

## Baseline on main (2026-09-23)

Gate **37 steps, exit 0** (`menus` added this session). Map is the owner's
authored labyrinth, `res://amethyst_labyrinth/` via `src/arena/dungeon_arena.tscn`:
77.2 m square, 945 meshes, 96 lights, 0 chokepoints, 54/54 spawns route to the
player, 6/6 caches. The procedural cave no longer ships; its generator stays in
arena.gd and keeps its own three scoped checks (arena, navmesh, placement).

PC only: keyboard and mouse, no gamepad anywhere.

## In flight

Nothing. Player-side animation pass complete and merged.

## Transform ownership (read before any camera/weapon animation)

- camera.position / rotation.y / rotation.z → `_tick_shake` (zeroes when idle)
- camera.rotation.x → look pitch + weapon recoil
- player.rotation.y → look yaw; head.rotation.x → look pitch
- head.position.y → `_tick_eye_height` (stance − landing offset)
- head.rotation.z → `_tick_lean`
- head.position.x/z → `_tick_flinch`
- weapon.position → one line: sway + bob + melee + reload + fire kick
- weapon.rotation.x → fire tip; weapon.rotation.z → reload roll
- FREE: nothing obvious on the player rig — compose, do not add writers

## Done this session (all merged, all measured)

- Mouse look: crosshair ColorRects ate every motion event (MOUSE_FILTER_STOP at
  screen centre). Needs the owner's hands on a trackpad to confirm.
- Minimap: sampled at 1 m instead of 4 m; was a solid square (100% fill).
- Spawns scored by route length; ceiling 45 m from a 4×3 seed sweep.
- Kill income routed across the arsenal (was held-weapon only): produces the
  forced switches the design asks for; Scavenger diagnosis did not survive.
- Staged menu PLAY → mode → difficulty, STATS screen, lifetime totals.
- Landing dip and strafe lean.
- Viewmodel: melee jab, reload dip and roll, per-weapon fire kick blended
  across bursts, decaying muzzle flash. Directional hit flinch.
- Tests can no longer change the real settings.cfg or records.cfg
  (UserDataGuard, proven in a sandbox both ways).

## Open

- Scavenger / progression: not currently the problem; revisit after playtest.
- Menu backdrop is dim — owner's call whether to light it.
- Records save: a probe of mine wrote to the real user:// file; backup kept at
  `app_userdata/LAST MAGAZINE/records.cfg.backup-20260922-224642`.
- Deaths-by-zombie-kind stat not recorded: damage path carries no attacker.

## Standing rules

- Agents: tight briefs, exact line pointers, "edit first", report early.
  Verify every claim against code — a report is not evidence.
- Judge the gate by exit code only. Probes use a private HOME.
- Blender geometry is the source of truth; integrate, never redesign.
- New gate checks only for real regressions or high-risk systems.
