# Active session state

<!-- STATUS -->
Epic: Early Access push
Feature: QA bug hunt
Task: qa-lead agent hunting cross-system defects; lead reviewing
<!-- /STATUS -->

## Landed on main — all gated at 33 steps, 28 verification scripts

| System | What it does | Evidence |
|---|---|---|
| Movement | walk/sprint/crouch, step assist, speed ladder vs zombie kinds | 13 assertions |
| Collision | dressing solid, per-mesh fitted boxes | audit + containment sweep |
| Map ring | outer ring joining all four arms | chokepoints 22 -> 14 |
| Cave dressing | medkits in alcoves, 11 junction identities, 10 gate landmarks | audits green |
| Weapons | pistol/shotgun/rifle, separate reserves, timed swap | gate |
| Zombies | 5 kinds with per-kind rules | 14 assertions |
| Interaction | E, timed holds, medkits | 8 assertions |
| Minimap | earned reveal, conditional markers | 6 assertions |
| Menus | controls screen from InputMap | 6 assertions, all 23 actions |
| Flashlight | costs 45% more sight range | asserted at the zombie |
| Audio | per-weapon shots, Screamer alarm | clips generated |

## Current measurements

| Measure | Value |
|---|---|
| walkable cells | 238 |
| connected areas | 1 |
| chokepoints | 14 (6%) |
| spawns reaching player | 55/55 |
| caches reachable | 8/8 |
| containment | 232 cells x 16 sweeps, 0 escapes |
| frame time | 6.89ms mean, 1.62ms physics (budget 16.6) |
| stress: 55 zombies | 6.95ms mean, all close on player |

## Design decisions agents made that improved on the brief

- The minimap's reveal radius is tied to the torch (4 cells unlit, 7 lit), so
  the map sits inside the flashlight bargain rather than beside it.
- Enemy markers only for HUNTING or within 8m, so information is symmetric —
  a marker is a warning, not an advantage, and a Stalker circling two rooms
  away stays invisible.
- Gate arches are SHELL_BACKED rather than collider-fitted: an AABB box around
  an arch is a solid wall, so fitting them would seal the corridors they frame.
- The torch HUD caption reads its "+45%" from `lit_visibility_scale` rather
  than a typed literal, so retuning cannot leave the HUD quoting an old figure.

## What running six agents in parallel taught us

- There is a hard ~20-turn ceiling per agent, sometimes 10. Three agents lost
  entire budgets by hitting it with nothing committed. Every brief now orders a
  commit the moment the gate is green, and resumption messages repeat it.
- A session-wide rate limit can kill every agent at once. Salvage by committing
  their worktrees from the lead session with `git -C <worktree> add -A`.
- Agents commit to their own `worktree-agent-<id>` branch, not always to the
  named feature branch. Merge by SHA when the named branch looks stale.
- Open-ended design-and-explore briefs fail at this budget. The map agent burned
  two full budgets producing nothing; the lead implemented the ring directly in
  a fraction of the time. Briefs must be prescriptive.
- Rescued WIP is not verified work. Merging the audio agent's rescue broke ten
  gate steps, because its generator had never been run.

## Still to do

- Objectives and progression (currently a timed extraction/hold-out clock)
- Exploration rewards beyond the two alcove medkits
- Full playthrough from main menu
- Final polish and Early Access readiness review

## Known open items

- Ceiling checked with a pitched capture: faceted rock, warm lamp pools,
  stalactites and hanging fixtures. The earlier "flat black" note was wrong —
  it came from a forward-facing shot where the ceiling is simply out of the
  light, which is correct for a cave. No work needed.
- `corridor-wide*`, `stairs-wide`, `template-wall-*` remain unused kit pieces.
- The four ring-corner gates were verified from above, not at eye height.
- 191 duplicate asset files (`* 2.glb`, 3.5MB) gitignored and still on disk.
