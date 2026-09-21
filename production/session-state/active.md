# Active session state

<!-- STATUS -->
Epic: Early Access push
Feature: HUD/minimap and cave dressing
Task: Two agents running; lead reviewing and integrating
<!-- /STATUS -->

## Landed on main

| Commit | What |
|---|---|
| `a7ac207` | Phase 2 movement: stance system, step assist, speed ladder |
| `e2fb635` | Phase 3 collision: dressing solid, collision audit gated |
| `0254195` | tools: route + containment audits |
| `882ed56` | tools: zombie stress test across every spawn point |
| weapons | three guns, three separate reserves |
| `26b616d` | map: outer ring, chokepoints 22 -> 14 |
| `eaba3bc` | interaction: E, medkits, cache resupply as a hold |
| `e794e80` | zombies: Stalker + Screamer, per-kind rules |
| menus | controls screen generated from the InputMap |
| `ed58f4a` | flashlight now costs 45% more sight range |

## Current measurements

| Measure | Value |
|---|---|
| walkable cells | 238 |
| connected areas | 1 |
| chokepoints | 14 (6% of cells) |
| zombie spawns reaching player | 55/55 |
| caches reachable | 8/8 |
| containment | 232 cells x 16 sweeps, 0 escapes |
| frame time | 6.92ms mean (budget 16.6) |
| stress: 55 zombies at once | 6.95ms mean, all close on player |

## Agents in flight

| Agent | Branch | Owns |
|---|---|---|
| ui-programmer | `feat/hud-minimap` | `src/ui/hud.*` |
| godot-specialist | `feat/cave-dressing` | `src/arena/arena.gd` |

## Lessons that changed how this is run

- Agents have a hard ~20-turn ceiling. Three lost all work by hitting it with
  nothing committed. Every brief now orders a commit the moment the gate is
  green, and resumption messages repeat it.
- A session-wide rate limit killed four agents simultaneously. Salvage by
  committing their worktrees from the lead session with `git -C <worktree>`.
- Open-ended design-and-explore tasks fail at this turn budget. The map agent
  burned two full budgets producing nothing; the ring was implemented directly
  by the lead in a fraction of the time. Briefs must be prescriptive.

## Still to do

- Objectives and progression (the round is currently a timed hold-out)
- Exploration rewards beyond the two alcove medkits
- Audio pass: weapon sounds per kind, zombie kind voices, spatial cues
- Performance pass and a full playthrough
- Bug hunt, final polish, readiness review

## Known open items

- The pistol viewmodel is Kenney's default purple/white and clashes badly with
  the grounded cave palette. Needs a tint pass.
- The ceiling reads as flat black in gameplay screenshots.
- `Medkit.spawn()` exists but nothing is placed in the level yet — assigned to
  the cave dressing agent.
- 191 duplicate asset files (`* 2.glb`, 3.5MB, byte-identical) are gitignored
  and still on disk.
