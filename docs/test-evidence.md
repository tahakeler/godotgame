# Test Evidence

Required by the assignment: *"Reproduce one normal and one boundary case per
feature, such as zero health. Compare expected and actual results: four checks
total."*

All four checks are automated in `tests/feature_tests.gd` and run as part of
`tools/check.sh`, so a broken feature blocks a merge rather than being noticed
later.

**Reproduce:**

```bash
/Applications/Godot47.app/Contents/MacOS/Godot --headless --script tests/feature_tests.gd
```

---

## Results — 4 checks, 4 passed, 0 failed

### Feature 1 — Player Health

**Normal case** — `player_health_zombie_contact_reduces_health`

| | |
|---|---|
| **Setup** | Player at full health (100) |
| **Action** | One zombie contact hit (12 damage) |
| **Expected** | `absorbed=12.0, health=88.0, dead=false` |
| **Actual** | `absorbed=12.0, health=88.0, dead=false` |
| **Result** | PASS |

**Boundary case** — `player_health_zero_health_ends_round`

| | |
|---|---|
| **Setup** | Player at full health, invulnerability disabled |
| **Action** | Apply 150 damage (well past the 100 pool), then damage the corpse for 25 more |
| **Expected** | `health=0.0, dead=true, died_signals=1, post_death_damage=0.0` |
| **Actual** | `health=0.0, dead=true, died_signals=1, post_death_damage=0.0` |
| **Result** | PASS |

Health floors at zero rather than going negative, `died` fires exactly once
(not repeatedly), and a dead player absorbs no further damage.

### Feature 2 — Ammunition and Reload

**Normal case** — `weapon_fire_with_ammo_decrements_magazine`

| | |
|---|---|
| **Setup** | Full magazine (8 rounds) |
| **Action** | Fire once |
| **Expected** | `fired=true, magazine=7` |
| **Actual** | `fired=true, magazine=7` |
| **Result** | PASS |

**Boundary case** — `weapon_fire_with_empty_magazine_is_blocked`

| | |
|---|---|
| **Setup** | Magazine set to 0 |
| **Action** | Attempt to fire |
| **Expected** | `fired=false, magazine=0, dry_fired=1` |
| **Actual** | `fired=false, magazine=0, dry_fired=1` |
| **Result** | PASS |

The shot is blocked, the count cannot go negative, and `dry_fired` fires so the
HUD can explain *why* nothing happened.

---

## Additional checks (beyond the required four)

Also in `tests/feature_tests.gd`:

| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| `weapon_reload_refills_magazine_from_reserve` | `reload=true, magazine=8, reserve=19` | same | PASS |
| `weapon_reload_with_empty_reserve_is_blocked` | `reload=false, magazine=0, fully_dry=true` | same | PASS |

Integration checks in `tests/manual/`:

| Check | What it guards |
|-------|----------------|
| `verify_project.gd` | Input actions and required scenes exist |
| `verify_arena.gd` | Navmesh bakes with polygons — a zero-polygon bake raises no error and just leaves zombies standing still |
| `verify_zombies.gd` | Zombies spawn, navigate toward the player, and award ammo on death |
| `verify_game_loop.gd` | Kills shorten extraction, clock-zero wins, death loses, and restart clears every system |

The restart check dirties ammo, health, clock, kills, and live zombies, then
asserts all of it is restored — stale state there would present as "the game
gets harder every time you retry" rather than as an obvious bug.

---

## Manual verification

Rendering cannot be checked headless. `tools/capture_screenshot.gd` boots a
scene and writes a frame to disk:

```bash
/Applications/Godot47.app/Contents/MacOS/Godot --path . \
  --script tools/capture_screenshot.gd --resolution 1280x720 \
  -- --scene=res://src/core/game.tscn --out=res://shot.png --delay=7.5
```

This is how the unplayably dark lighting was caught — every automated check
passed while the arena was too dark to see.
