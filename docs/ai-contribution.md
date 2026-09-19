# AI Contribution

Required by the assignment: *"Develop at least one feature through MCP and
identify the assistant's scene or script changes."*

This project was developed with **Claude Code** (Claude Opus 5) acting as an AI
assistant through the terminal, driven by the
[Claude Code Game Studios](https://github.com/Donchitos/Claude-Code-Game-Studios)
agent framework. Claude Code operates over a tool protocol (file read/write,
shell, git) — the same integration model MCP defines for exposing tools to an
assistant.

---

## Which parts the assistant wrote

Every file below was authored by the assistant. Direction, decisions, and
acceptance were the developer's.

### Feature 1 — Player Health (AI-developed)

| File | What the assistant wrote |
|------|--------------------------|
| `src/gameplay/health.gd` | The entire shared Health component — damage, death, invulnerability window, reset |
| `src/gameplay/player/player.gd` | `take_damage()`, `get_angle_to_source()`, the `damage_taken` / `died` signals, health reset in `reset_to_spawn()` |
| `src/gameplay/player/player.tscn` | Added the `Health` child node (max 100, 0.45s invulnerability) |
| `src/gameplay/zombie/zombie.gd` | `_try_attack()` — the contact damage that drives this feature |
| `src/ui/hud.gd` | `_on_health_changed()`, `_on_damage_taken()`, `_draw_damage_markers()` |

### Feature 2 — Ammunition and Reload (AI-developed)

| File | What the assistant wrote |
|------|--------------------------|
| `src/gameplay/weapon/weapon.gd` | The entire weapon — `try_fire()`, `try_reload()`, `_tick_reload()`, `add_reserve_ammo()`, raycast, tracer, recoil |
| `src/gameplay/weapon/weapon.tscn` | The whole viewmodel: receiver, barrel, grip, sight, muzzle, flash light |
| `src/ui/hud.gd` | `_on_ammo_changed()`, `_on_reload_started()`, `_on_dry_fired()` |

### Everything else the assistant authored

| Area | Files |
|------|-------|
| Arena | `src/arena/arena.gd`, `src/arena/arena.tscn` |
| Player control | `src/gameplay/player/player.gd`, `player.tscn` |
| Zombies | `src/gameplay/zombie/zombie.gd`, `zombie.tscn`, `zombie_spawner.gd` |
| Game loop | `src/core/game.gd`, `game.tscn` |
| Settings | `src/core/game_settings.gd` |
| Interface | `src/ui/hud.gd/.tscn`, `main_menu.gd/.tscn`, `pause_menu.gd/.tscn`, `settings_panel.gd/.tscn` |
| Tests | `tests/feature_tests.gd`, `tests/manual/*.gd` |
| Tooling | `tools/check.sh`, `tools/capture_screenshot.gd` |
| Project config | `project.godot`, `icon.svg` |

---

## Bugs the assistant found and fixed

These are worth knowing about, because each was invisible until something
specifically looked for it.

| Problem | How it presented | Fix |
|---------|------------------|-----|
| Navmesh agent dimensions were not multiples of `cell_size` | No error. The baker silently rounded them, so the mesh did not match the configured values | Snapped `agent_radius`/`height`/`max_climb` to the voxel grid |
| Navmesh `cell_size` did not match the navigation map's | Warning only. The mesh rasterised against a different grid than agents query | Matched the project default of 0.25 |
| Duplicate `weapon 2.gd` from a file-sync conflict | Duplicate `class_name Weapon` failed the **entire project** at parse time | Deleted the identical copies; added a gitignore rule |
| `Settings` autoload referenced directly in gameplay code | Autoloads do not exist under `--script`; the reference failed to *compile* and took the whole headless test suite down | `GameSettings.instance()` runtime lookup with a `class_name` for constants |
| Tests asserting inside `_initialize()` | `_ready()` has not run yet, so every exported default read as zero | Moved assertions to the first processed frame |
| Tests using `queue_free()` before `quit()` | Deferred frees never ran; the engine reported leaked RIDs, which reads as a real failure | Free synchronously |
| Zombie test had no timeout | Spun forever when the scene failed to load — 12MB log, manual kill | Added a watchdog |
| Arena was too dark to play | Every headless check passed. Only a rendered frame showed it | Raised light energy and albedo, dropped the ACES white point |

The last one is the important one: **the automated checks passed the entire
time the game was unplayably dark.** Rendering had to be looked at directly.

---

## How to verify this yourself

```bash
./tools/check.sh                    # full gate: import, arena, zombies, loop, features, boot
```

Git history shows the work branch by branch — `git log --oneline --graph main`.
