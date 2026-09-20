# Active session state

<!-- STATUS -->
Epic: Early Access push
Feature: Map connectivity + arsenal + zombie archetypes
Task: Three agents running in parallel; lead reviewing
<!-- /STATUS -->

## Where the project is

Phases 1-3 of the 42-phase brief are merged to `main`:

- Phase 1 camera — merged `3ad9a52`
- Phase 2 movement (stance system, step assist, speed ladder) — merged `a7ac207`
- Phase 3 collision (dressing made solid, collision audit gated) — merged `e2fb635`

## Baselines measured before the map rebuild

Recorded so the map agent's work can be judged against numbers rather than
against a screenshot.

| Measure | Value | Tool |
|---|---|---|
| walkable cells | 190 | `tools/map_graph.gd` |
| connected areas | 1 | `tools/map_graph.gd` |
| dead-end cells | 2 | `tools/map_graph.gd` |
| terminal arms (must backtrack) | 4 | read from the ASCII map |
| chokepoints (no way round) | 22 — 12% of cells | `tools/audit_routes.gd` |
| zombie spawns that reach the player | 55/55 | `tools/audit_routes.gd` |
| caches the player can reach | 6/6 | `tools/audit_routes.gd` |
| worst detour | 1.5x straight line | `tools/audit_routes.gd` |
| containment | 184 cells x 16 sweeps, 0 escapes | `tools/audit_collision.gd` |
| frame time | ~12.4ms mean at 22 zombies (budget 16.6) | `tools/benchmark.gd` |

The headline problem is the four terminal arms and the 22 chokepoints: the map
is a plus-shape with two rings, so most of it can only be entered and left the
same way.

## Agents in flight

Each in its own git worktree, on its own branch, with non-overlapping files.

| Agent | Branch | Owns | Must not touch |
|---|---|---|---|
| godot-specialist | `feat/map-connectivity` | `src/arena/arena.gd` | weapons, hud, zombies |
| gameplay-programmer | `feat/weapon-arsenal` | `src/gameplay/weapon/*`, input map, ammo readout | arena, zombies |
| ai-programmer | `feat/zombie-archetypes` | `src/gameplay/zombie/*` | arena, weapons, hud |

Known merge hazard: all three may add a `run_step` line to `tools/check.sh`.
Expect a small conflict there and resolve by keeping every step.

## Sequencing still to respect

- Navmesh and zombie traversal verification wait for the map to land.
- Spawn-zone placement waits for the map.
- Minimap waits for the map.
- HUD/minimap pass waits for the arsenal, because it will own `hud.gd` after.
- Combat feedback polish waits for the weapon systems to be reliable.

## Decisions taken without asking

- The Kenney Modular Dungeon Kit was NOT downloaded. The cave kit has 25 unused
  models (`corridor-junction`, the whole `corridor-wide-*` family,
  `corridor-transition`, the three `gate*` pieces, `ladder`), which is far more
  headroom than the map currently uses and carries no risk of clashing with the
  established art direction. Revisit only if the cave kit runs out.
- The user's colour grade, procedural stone shader and timber stairs are
  treated as fixed art direction and preserved.
