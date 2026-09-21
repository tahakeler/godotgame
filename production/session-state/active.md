# Active session state

<!-- STATUS -->
Epic: Early Access push
Feature: melee, encounter tuning, HUD legibility
Task: three agents in parallel; lead reviewing and integrating
<!-- /STATUS -->

## Baseline on main

Gate: 37 steps, 32 verify scripts, exit 0. Frame time ~6.9ms against 16.6ms.
Map: 238 cells, 1 area, 14 chokepoints, 55/55 spawns reach the player, 8/8
caches, containment holds across 232 cells.

## Agent roster and capabilities

Checked, not assumed. Two agents have NO Bash and can only do design work.

| Agent | Type | Bash | Owns / knows |
|---|---|---|---|
| a9d4d698 | gameplay-programmer | yes | weapons, ammo |
| a4261a7d | ai-programmer | yes | zombies, archetypes |
| ae266313 | ui-programmer | yes | HUD, minimap |
| a30dce6b | ui-programmer | yes | menus, settings |
| a7be4588 | gameplay-programmer | yes | interaction, player input |
| a4d64d49 | gameplay-programmer | yes | objectives, relay |
| a89e10a1 | qa-lead | yes | QA |
| abadd035 | qa-lead | yes | QA, concurrency findings |
| a9689d28 | godot-specialist | yes | arena dressing |
| aa616053 | sound-designer | **NO** | audio design only |
| a2b68fec | game-designer | **NO** | specs only |
| af6da315 | godot-specialist | — | TERMINATED: two budgets, zero output |

## In flight

| Agent | Branch | Owns | Must not touch |
|---|---|---|---|
| a9d4d698 | `feat/melee` | weapon/*, input map, game.gd audio, sound_bank | zombie/*, hud.gd, arena.gd |
| a4261a7d | `tune/mixed-encounters` | zombie/*, verify_zombie_* | weapon/*, hud.gd, arena.gd |
| ae266313 | `feat/hud-legibility` | hud.gd, hud.tscn | weapon/*, zombie/*, game.gd, arena.gd |

## Standing constraints

- **Do not touch `src/arena/arena.gd`.** The owner is building real maps in
  Blender. The current map is a development/testing environment only. When the
  Blender maps arrive, the geometry is the source of truth and agents handle
  Godot integration only.
- **Do not grow the gate.** 36+ steps and 146+ assertions is enough. New checks
  only for a real regression, a high-risk system or a concurrency issue.
- **Judge the gate by its exit code**, never by grepping its output. A previous
  merge happened on a red gate because `&&` chained on grep's exit status,
  which succeeded because it *found* the word FAIL.
- Every brief must be small, concrete and finishable inside ~20 turns. Agents
  must commit the moment the gate is green.

## Two shared-state bugs, both fixed

Both produced failures that reproduced nowhere except inside the gate.

- **Logs**: `LOG_DIR` was one fixed path for every worktree, so a run graded a
  log another worktree had just overwritten. Now keyed by a checksum of the
  checkout path.
- **user://**: settings.cfg and records.cfg were global to the machine. Godot
  has no --userdir flag, so the gate now gives itself a private HOME. Two
  non-obvious requirements: the app_userdata path must be created all the way
  down first, and XDG_DATA_HOME must be left alone on macOS. Verified under
  real concurrency — main's gate exits 0 with 11 agent worktrees active.

## Decisions taken as lead

- **Build the melee rather than patch dry_resupply.** `_fire()` already has the
  machinery — a ray on mask 1|4 excluding the owner, `take_damage`, and the
  `impacted` / `target_hit` signals wired to effects and audio. A shallow
  addition, so the "disproportionate architectural work" escape does not apply.
- **The relay keeps arena.gd untouched.** Relay cells live in
  `RelayObjective.RELAY_PLACEMENTS` and beacons are built at runtime from
  `arena._cell_to_world(cell)`, so the Blender handoff stays clean.

## Needs 60 seconds from the owner

Trackpad look was reading `event.relative`, which Godot divides by the
`canvas_items` stretch scale — about 1.6 on a Retina MacBook in fullscreen, so
a swipe reported two-thirds of the real motion. Now on `screen_relative`.
Headless has no stretch, so the test proves the code prefers the right value,
not what it feels like. Wants a hands-on fullscreen check.

## Next, once the three in flight land

Encounter pacing and wave composition, objective progression, combat feedback,
interaction and pickup feedback, then Blender map integration when it arrives,
lighting and audio atmosphere, performance, full playthrough, bug hunt, polish,
readiness review.
